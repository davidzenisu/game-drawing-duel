import secrets
import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Path, status
from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.auth import CurrentPlayer
from app.database import get_db, utc_now
from app.models import (
    ChallengerPrompt,
    Character,
    DayEnd,
    Fight,
    Fighter,
    Hurry,
    Player,
    Pull,
    PullGrant,
    Server,
    ServerSeat,
    SetupAssignment,
    Upgrade,
    Vote,
)
from app.rules import SERVER_CODE_LENGTH
from app.schemas import SeatResponse, ServerCreate, ServerResponse
from app.setup import assign_setup
from app.storage import Files, delete_quietly

router = APIRouter(prefix="/servers", tags=["servers"])

Code = Annotated[str, Path(pattern=rf"^\d{{{SERVER_CODE_LENGTH}}}$")]
DbSession = Annotated[Session, Depends(get_db)]

# Retries when a random code is already taken.
_CODE_ATTEMPTS = 10


def _new_code() -> str:
    return "".join(str(secrets.randbelow(10)) for _ in range(SERVER_CODE_LENGTH))


def phase(server: Server) -> Literal["lobby", "setup", "running", "cancelled"]:
    if server.cancelled_at is not None:
        return "cancelled"
    if server.launched_at is not None:
        return "running"
    return "lobby" if server.setup_started_at is None else "setup"


def require_not_launched(server: Server) -> None:
    if server.launched_at is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="The game already launched"
        )


def server_response(server: Server, player: Player) -> ServerResponse:
    your_seat = next((s for s in server.seats if s.player_id == player.id), None)
    return ServerResponse(
        code=server.code,
        created_at=server.created_at,
        is_test=server.is_test,
        is_admin=server.admin_id == player.id,
        phase=phase(server),
        cancelled_by=server.cancelled_by,
        your_position=your_seat.position if your_seat else None,
        seats=[
            SeatResponse(
                position=s.position,
                name=s.name,
                joined=s.player_id is not None,
                setup_done=s.setup_done_at is not None,
            )
            for s in server.seats
        ],
    )


def load_server(session: Session, code: str, *, cancelled_ok: bool = False) -> Server:
    """The server with `code`; `410 Gone` once it was cancelled, unless
    `cancelled_ok`."""
    server = session.scalar(
        select(Server).where(Server.code == code).options(selectinload(Server.seats))
    )
    if server is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No server with this code")
    if server.cancelled_at is not None and not cancelled_ok:
        raise HTTPException(status.HTTP_410_GONE, detail="The server was cancelled")
    return server


def your_seat(server: Server, player_id: uuid.UUID) -> ServerSeat:
    seat = next((s for s in server.seats if s.player_id == player_id), None)
    if seat is None:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, detail="You haven't joined this server"
        )
    return seat


@router.post("", response_model=ServerResponse, status_code=status.HTTP_201_CREATED)
def create_server(
    body: ServerCreate, player: CurrentPlayer, session: DbSession
) -> ServerResponse:
    """Creates a server with the full list of players; you are its admin."""
    names = [player.first_name, *body.other_names]
    if len({name.casefold() for name in names}) != len(names):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Every player needs a different name",
        )
    for _ in range(_CODE_ATTEMPTS):
        server = Server(code=_new_code(), admin_id=player.id, is_test=body.is_test)
        server.seats = [
            ServerSeat(position=position, name=name)
            for position, name in enumerate(names)
        ]
        server.seats[0].player_id = player.id
        server.seats[0].joined_at = func.now()
        session.add(server)
        try:
            session.commit()
        except IntegrityError:
            session.rollback()
            continue
        return server_response(load_server(session, server.code), player)
    raise HTTPException(
        status.HTTP_503_SERVICE_UNAVAILABLE, detail="Could not generate a server code"
    )


@router.get("/mine", response_model=list[ServerResponse])
def my_servers(player: CurrentPlayer, session: DbSession) -> list[ServerResponse]:
    """The servers you joined, newest first. A cancelled one stays until you
    dismiss it."""
    servers = session.scalars(
        select(Server)
        .join(ServerSeat)
        .where(ServerSeat.player_id == player.id, ServerSeat.dismissed_at.is_(None))
        .options(selectinload(Server.seats))
        .order_by(Server.created_at.desc())
    ).all()
    return [server_response(server, player) for server in servers]


@router.get("/{code}", response_model=ServerResponse)
def get_server(code: Code, player: CurrentPlayer, session: DbSession) -> ServerResponse:
    """The roster and who joined. Knowing the code is the invitation."""
    return server_response(load_server(session, code, cancelled_ok=True), player)


@router.post("/{code}/seats/{position}/claim", response_model=ServerResponse)
def claim_seat(
    code: Code,
    position: Annotated[int, Path(ge=0)],
    player: CurrentPlayer,
    session: DbSession,
) -> ServerResponse:
    """Joins the server as the player the admin listed at `position`."""
    server = load_server(session, code)
    require_not_launched(server)
    seat = next((s for s in server.seats if s.position == position), None)
    if seat is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such seat")
    current = next((s for s in server.seats if s.player_id == player.id), None)
    if current is not None:
        if current.position == position:
            return server_response(server, player)
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="You already joined this server"
        )
    # Only claims a free seat, even if someone else claims it at the same time.
    claimed = session.execute(
        update(ServerSeat)
        .where(ServerSeat.id == seat.id, ServerSeat.player_id.is_(None))
        .values(player_id=player.id, joined_at=func.now())
    ).rowcount
    if not claimed:
        session.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, detail="This seat is taken")
    if server.is_test and server.setup_started_at is not None:
        # Joining a test session late: draw along with everyone who joined.
        session.refresh(seat)
        session.add_all(assign_setup(server, [seat]))
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="You already joined this server"
        ) from error
    session.expire_all()
    return server_response(load_server(session, code), player)


def _delete_game_data(session: Session, server: Server) -> list[uuid.UUID]:
    """Deletes everything played on `server` but the server and its seats;
    returns the ids of the deleted characters, whose drawings to delete."""
    seat_ids = [s.id for s in server.seats]
    character_ids = list(
        session.scalars(select(Character.id).where(Character.server_id == server.id))
    )
    fight_ids = select(Fight.id).where(Fight.owner_seat_id.in_(seat_ids))
    for statement in (
        delete(Vote).where(Vote.fight_id.in_(fight_ids)),
        delete(Fighter).where(Fighter.fight_id.in_(fight_ids)),
        delete(Fight).where(Fight.owner_seat_id.in_(seat_ids)),
        delete(Upgrade).where(Upgrade.seat_id.in_(seat_ids)),
        delete(Pull).where(Pull.seat_id.in_(seat_ids)),
        delete(PullGrant).where(PullGrant.seat_id.in_(seat_ids)),
        delete(Hurry).where(Hurry.sender_seat_id.in_(seat_ids)),
        delete(DayEnd).where(DayEnd.seat_id.in_(seat_ids)),
        delete(ChallengerPrompt).where(ChallengerPrompt.author_seat_id.in_(seat_ids)),
        delete(Character).where(Character.server_id == server.id),
        delete(SetupAssignment).where(SetupAssignment.artist_seat_id.in_(seat_ids)),
    ):
        session.execute(statement)
    return character_ids


@router.delete("/{code}", status_code=status.HTTP_204_NO_CONTENT)
def cancel_server(
    code: Code, player: CurrentPlayer, session: DbSession, files: Files
) -> None:
    """Cancels the server for everyone and deletes all its drawings and game
    data, at any point of the game.

    Any player who joined can, e.g. the admin when setting it up went wrong
    or a player dropping out. The server and its seats stay, marked
    cancelled, so the others find out when they return (see `dismiss`).
    """
    server = load_server(session, code)
    seat = your_seat(server, player.id)
    # Locked, so a second cancel at the same time waits and then finds out.
    session.scalar(select(Server.id).where(Server.id == server.id).with_for_update())
    session.refresh(server)
    if server.cancelled_at is not None:
        raise HTTPException(status.HTTP_410_GONE, detail="The server was cancelled")
    character_ids = _delete_game_data(session, server)
    now = utc_now()
    server.cancelled_at = now
    server.cancelled_by = seat.name
    seat.dismissed_at = now
    session.commit()
    for character_id in character_ids:
        delete_quietly(files, str(character_id))


@router.post("/{code}/dismiss", status_code=status.HTTP_204_NO_CONTENT)
def dismiss_cancelled_server(
    code: Code, player: CurrentPlayer, session: DbSession
) -> None:
    """You saw that the server was cancelled: it's no longer one of yours."""
    server = load_server(session, code, cancelled_ok=True)
    seat = your_seat(server, player.id)
    if server.cancelled_at is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="The server wasn't cancelled"
        )
    if seat.dismissed_at is None:
        seat.dismissed_at = utc_now()
        session.commit()
