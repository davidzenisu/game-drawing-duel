"""Housekeeping for the accounts with the admin permission
(`auth.ADMIN_PERMISSION`)."""

import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import or_, select
from sqlalchemy.orm import aliased, selectinload

from app import gifts, speed
from app.auth import Auth0Subject, require_server_admin
from app.database import utc_now
from app.days import calendar_date
from app.deps import DbSession, load_server
from app.game_data import delete_game_data
from app.models import Character, Player, Server, ServerSeat
from app.schemas import (
    AdminDrawing,
    AdminPlayer,
    AdminServer,
    CleanupResponse,
    GiftSend,
    GiftSent,
)
from app.storage import FileNotFound, Files, StorageUnavailable, delete_quietly

router = APIRouter(
    # Not /admin: the Azure Functions host keeps every path under /admin for
    # its own API and answers 404 before the app sees the request.
    prefix="/manage",
    tags=["admin"],
    dependencies=[Depends(require_server_admin)],
)

# Test sessions and speed mode sessions are deleted once they're this old.
SHORT_LIVED_FOR = timedelta(days=1)


@router.post("/servers/cleanup", response_model=CleanupResponse)
def clean_up_servers(session: DbSession, files: Files) -> CleanupResponse:
    """Deletes every test session and speed mode session created more than
    a day ago, with its seats, game data and drawings: they're one-offs."""
    stale = session.scalars(
        select(Server).where(
            or_(Server.is_test.is_(True), Server.mode == speed.SPEED),
            Server.created_at < utc_now() - SHORT_LIVED_FOR,
        )
    ).all()
    codes = []
    character_ids = []
    for server in stale:
        character_ids += delete_game_data(session, server)
        codes.append(server.code)
        session.delete(server)
    session.commit()
    for character_id in character_ids:
        delete_quietly(files, str(character_id))
    return CleanupResponse(deleted=sorted(codes))


@router.get("/servers", response_model=list[AdminServer])
def list_servers(session: DbSession) -> list[AdminServer]:
    """Every server that wasn't cancelled, newest first, with its players:
    what a gift can go to."""
    servers = session.scalars(
        select(Server)
        .where(Server.cancelled_at.is_(None))
        .order_by(Server.created_at.desc())
        .options(selectinload(Server.seats))
    )
    return [
        AdminServer(
            code=server.code,
            speed=speed.is_speed(server),
            launched=server.launched_at is not None,
            players=[
                AdminPlayer(
                    position=s.position, name=s.name, joined=s.player_id is not None
                )
                for s in sorted(server.seats, key=lambda s: s.position)
            ],
        )
        for server in servers
    ]


@router.post("/gifts", response_model=GiftSent, status_code=status.HTTP_201_CREATED)
def send_gift(body: GiftSend, subject: Auth0Subject, session: DbSession) -> GiftSent:
    """Gives pulls and stars outside the regular rewards, with a message (or
    just a message, with neither): to everyone on every server without
    `server_code`, else to everyone on that server, or only the players at
    `positions`. They see it on the app's notification board and get the
    pulls and stars once they accept it."""
    if body.server_code is None and body.positions is not None:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Pick a server to send to chosen players",
        )
    server = (
        None if body.server_code is None else load_server(session, body.server_code)
    )
    sender = session.scalar(select(Player.id).where(Player.auth0_id == subject))
    try:
        gift, count = gifts.send(
            session,
            sender,
            body.message,
            body.pulls,
            server,
            body.positions,
            stars=body.stars,
        )
    except gifts.GiftError as error:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(error)
        ) from error
    return GiftSent(id=gift.id, recipients=count)


@router.get("/servers/{code}/drawings", response_model=list[AdminDrawing])
def list_drawings(code: str, session: DbSession) -> list[AdminDrawing]:
    """Every drawing of a server: the initial setup drawings first, then each
    day's challengers, in roster order of their artists."""
    server = load_server(session, code)
    artist = aliased(ServerSeat)
    subject = aliased(ServerSeat)
    rows = session.execute(
        select(Character, artist.name, subject.name)
        .join(artist, artist.id == Character.artist_seat_id)
        .join(subject, subject.id == Character.subject_seat_id)
        .where(Character.server_id == server.id)
        .order_by(
            Character.day.is_not(None),
            Character.day,
            artist.position,
            Character.created_at,
        )
    ).all()
    return [
        AdminDrawing(
            id=character.id,
            day=character.day,
            date=None
            if character.day is None
            else calendar_date(server, character.day),
            artist=artist_name,
            subject=subject_name,
            title=character.title,
            rarity=character.rarity,
            prompt=character.prompt,
        )
        for character, artist_name, subject_name in rows
    ]


@router.get(
    "/characters/{character_id}/sketch",
    response_class=Response,
    responses={200: {"content": {"application/json": {}}}},
)
def get_any_sketch(
    character_id: uuid.UUID, session: DbSession, files: Files
) -> Response:
    """The strokes of any server's character, like the players' own
    `GET /characters/{id}/sketch`."""
    if session.get(Character, character_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such character")
    try:
        data = files.download(str(character_id))
    except FileNotFound as error:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="The drawing is missing"
        ) from error
    except StorageUnavailable as error:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="Couldn't load the drawing"
        ) from error
    return Response(
        data,
        media_type="application/json",
        headers={"Cache-Control": "private, max-age=31536000, immutable"},
    )
