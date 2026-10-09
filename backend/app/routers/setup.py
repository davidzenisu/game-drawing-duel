"""The initial drawing setup: starting it, the assignments and the drawings."""

import logging
import uuid
from typing import Annotated

from fastapi import APIRouter, HTTPException, Path, status
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.auth import CurrentPlayer
from app.models import Character, Server, ServerSeat, SetupAssignment
from app.routers.servers import Code, DbSession, load_server, server_response
from app.rules import SetupPrompt
from app.schemas import (
    AssignmentResponse,
    CharacterResponse,
    DrawingSubmit,
    ServerResponse,
)
from app.setup import assign_setup
from app.storage import Files, StorageUnavailable

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/servers", tags=["setup"])


def your_seat(server: Server, player_id: int) -> ServerSeat:
    seat = next((s for s in server.seats if s.player_id == player_id), None)
    if seat is None:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, detail="You haven't joined this server"
        )
    return seat


def _require_setup(server: Server) -> None:
    if server.setup_started_at is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="The setup hasn't started yet"
        )


def character_response(character: Character) -> CharacterResponse:
    return CharacterResponse(
        id=character.id,
        title=character.title,
        rarity=character.rarity,
        prompt=character.prompt,
        artist_position=character.artist.position,
        subject_position=character.subject.position,
    )


@router.post("/{code}/setup", response_model=ServerResponse)
def start_setup(
    code: Code, player: CurrentPlayer, session: DbSession
) -> ServerResponse:
    """Starts the initial drawing setup for everyone. Admin only.

    Regular servers start once everyone joined; test sessions start with the
    players who joined so far.
    """
    server = load_server(session, code)
    if server.admin_id != player.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, detail="Only the admin can start the setup"
        )
    if not server.is_test and any(s.player_id is None for s in server.seats):
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Not everyone joined yet")
    # Only starts once, even if started twice at the same time.
    started = session.execute(
        update(Server)
        .where(Server.id == server.id, Server.setup_started_at.is_(None))
        .values(setup_started_at=func.now())
    ).rowcount
    if not started:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="The setup already started"
        )
    session.refresh(server)
    artists = [s for s in server.seats if s.player_id is not None]
    session.add_all(assign_setup(server, artists))
    session.commit()
    session.expire_all()
    return server_response(load_server(session, code), player)


@router.get("/{code}/assignments", response_model=list[AssignmentResponse])
def my_assignments(
    code: Code, player: CurrentPlayer, session: DbSession
) -> list[AssignmentResponse]:
    """Your drawings for the initial setup, with what you drew so far."""
    server = load_server(session, code)
    seat = your_seat(server, player.id)
    _require_setup(server)
    assignments = session.scalars(
        select(SetupAssignment)
        .where(SetupAssignment.artist_seat_id == seat.id)
        .options(selectinload(SetupAssignment.subject))
    ).all()
    characters = {
        c.assignment_id: c
        for c in session.scalars(
            select(Character)
            .where(Character.assignment_id.in_([a.id for a in assignments]))
            .options(selectinload(Character.artist), selectinload(Character.subject))
        )
    }
    # Every setup plan follows the order of the prompts.
    order = list(SetupPrompt)
    assignments = sorted(assignments, key=lambda a: order.index(SetupPrompt(a.prompt)))
    return [
        AssignmentResponse(
            id=a.id,
            prompt=a.prompt,
            subject_position=a.subject.position,
            based_on=a.based_on_id,
            character=character_response(characters[a.id])
            if a.id in characters
            else None,
        )
        for a in assignments
    ]


def _drawn(session: Session, assignment_id: int) -> Character | None:
    return session.scalar(
        select(Character).where(Character.assignment_id == assignment_id)
    )


@router.put(
    "/{code}/assignments/{assignment_id}/drawing", response_model=CharacterResponse
)
def submit_drawing(
    code: Code,
    assignment_id: Annotated[int, Path(ge=1)],
    body: DrawingSubmit,
    player: CurrentPlayer,
    session: DbSession,
    files: Files,
) -> CharacterResponse:
    """Draws, or redraws, one of your setup assignments.

    The sketch is stored as a file named after the new character's id; a
    redrawn character gets a new id and its old file is deleted.
    """
    server = load_server(session, code)
    seat = your_seat(server, player.id)
    _require_setup(server)
    assignment = session.get(SetupAssignment, assignment_id)
    if assignment is None or assignment.artist_seat_id != seat.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such assignment")
    if assignment.based_on_id is not None and not _drawn(
        session, assignment.based_on_id
    ):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="Draw the drawing this one is based on first",
        )
    prompt = SetupPrompt(assignment.prompt)
    character = Character(
        id=uuid.uuid4(),
        server_id=server.id,
        artist=seat,
        subject=assignment.subject,
        assignment_id=assignment.id,
        title=body.title,
        rarity=prompt.rarity.value,
        prompt=prompt.value,
    )
    try:
        files.upload(
            str(character.id),
            body.sketch.model_dump_json().encode(),
            content_type="application/json",
            metadata={
                "kind": "setup",
                "server": server.code,
                "prompt": prompt.value,
                "rarity": prompt.rarity.value,
                "artist_position": str(seat.position),
                "subject_position": str(assignment.subject.position),
            },
        )
    except StorageUnavailable as error:
        logger.exception("Storing a drawing failed")
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="Couldn't store the drawing"
        ) from error

    previous = _drawn(session, assignment.id)
    previous_id = previous.id if previous else None
    try:
        if previous is not None:
            session.delete(previous)
            session.flush()
        session.add(character)
        session.commit()
    except Exception as error:
        session.rollback()
        _delete_file(files, character.id)
        if isinstance(error, IntegrityError):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="This drawing was just changed elsewhere, try again",
            ) from error
        raise
    if previous_id is not None:
        _delete_file(files, previous_id)
    return character_response(character)


def _delete_file(files: Files, character_id: uuid.UUID) -> None:
    """Best effort: a file left behind costs storage, not correctness."""
    try:
        files.delete(str(character_id))
    except StorageUnavailable:
        logger.exception("Deleting the drawing %s failed", character_id)
