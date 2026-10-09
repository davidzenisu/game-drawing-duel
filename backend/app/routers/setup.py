"""The initial drawing setup: starting it, the assignments and the drawings."""

import logging
import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session, selectinload

from app.auth import CurrentPlayer
from app.drawings import save_character
from app.models import Character, Server, ServerSeat, SetupAssignment
from app.pulls import grant_launch_bonus
from app.routers.servers import (
    Code,
    DbSession,
    load_server,
    require_not_launched,
    server_response,
    your_seat,
)
from app.rules import SetupPrompt
from app.schemas import (
    AssignmentResponse,
    CharacterResponse,
    DrawingSubmit,
    ServerResponse,
)
from app.setup import assign_setup
from app.storage import Files, delete_quietly

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/servers", tags=["setup"])


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
        day=character.day,
        theme=character.theme,
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


def _drawn(session: Session, assignment_id: uuid.UUID) -> Character | None:
    return session.scalar(
        select(Character).where(Character.assignment_id == assignment_id)
    )


@router.put(
    "/{code}/assignments/{assignment_id}/drawing", response_model=CharacterResponse
)
def submit_drawing(
    code: Code,
    assignment_id: uuid.UUID,
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
    require_not_launched(server)
    if seat.setup_done_at is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="You already finished your setup"
        )
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
    previous = _drawn(session, assignment.id)
    previous_id = previous.id if previous else None

    def remove_previous() -> None:
        if previous is not None:
            session.delete(previous)
            session.flush()

    save_character(
        session,
        files,
        server,
        character,
        body.sketch,
        kind="setup",
        conflict="This drawing was just changed elsewhere, try again",
        before_insert=remove_previous,
    )
    if previous_id is not None:
        delete_quietly(files, str(previous_id))
    return character_response(character)


@router.post("/{code}/setup/done", response_model=ServerResponse)
def finish_setup(
    code: Code, player: CurrentPlayer, session: DbSession
) -> ServerResponse:
    """Finishes your setup drawings; they can't be redrawn anymore.

    The game launches once every player with setup drawings finished: all
    their characters form the pool, and each player's own drawings start
    their collection.
    """
    server = load_server(session, code)
    seat = your_seat(server, player.id)
    _require_setup(server)
    require_not_launched(server)
    # Finishing players wait for each other here, so the last one to finish
    # sees everyone else's and launches.
    session.scalar(select(Server.id).where(Server.id == server.id).with_for_update())
    artist_ids = set(
        session.scalars(
            select(SetupAssignment.artist_seat_id)
            .join(ServerSeat, ServerSeat.id == SetupAssignment.artist_seat_id)
            .where(ServerSeat.server_id == server.id)
        )
    )
    undrawn = session.scalar(
        select(func.count())
        .select_from(SetupAssignment)
        .outerjoin(Character, Character.assignment_id == SetupAssignment.id)
        .where(SetupAssignment.artist_seat_id == seat.id, Character.id.is_(None))
    )
    if undrawn:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="Finish all your drawings first"
        )
    if seat.setup_done_at is None:
        seat.setup_done_at = func.now()
        session.flush()
    session.refresh(server)
    if all(s.setup_done_at is not None for s in server.seats if s.id in artist_ids):
        server.launched_at = func.now()
        if server.is_test:
            server.test_day = 1
        grant_launch_bonus(
            session, [s for s in server.seats if s.player_id is not None]
        )
    session.commit()
    session.expire_all()
    return server_response(load_server(session, code), player)
