import secrets
import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Path, status
from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.auth import CurrentPlayer
from app.database import get_db
from app.models import Character, Player, Server, ServerSeat, SetupAssignment
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


def phase(server: Server) -> Literal["lobby", "setup", "running"]:
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


def load_server(session: Session, code: str) -> Server:
    server = session.scalar(
        select(Server).where(Server.code == code).options(selectinload(Server.seats))
    )
    if server is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No server with this code")
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
    """The servers you joined, newest first."""
    servers = session.scalars(
        select(Server)
        .join(ServerSeat)
        .where(ServerSeat.player_id == player.id)
        .options(selectinload(Server.seats))
        .order_by(Server.created_at.desc(), Server.id.desc())
    ).all()
    return [server_response(server, player) for server in servers]


@router.get("/{code}", response_model=ServerResponse)
def get_server(code: Code, player: CurrentPlayer, session: DbSession) -> ServerResponse:
    """The roster and who joined. Knowing the code is the invitation."""
    return server_response(load_server(session, code), player)


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


@router.delete("/{code}", status_code=status.HTTP_204_NO_CONTENT)
def cancel_server(
    code: Code, player: CurrentPlayer, session: DbSession, files: Files
) -> None:
    """Cancels the server for everyone, with all its drawings. Only before
    the launch.

    Any player who joined can, e.g. the admin when setting it up went wrong
    or a player dropping out. The others find out when they next refresh.
    """
    server = load_server(session, code)
    your_seat(server, player.id)
    require_not_launched(server)
    character_ids = session.scalars(
        select(Character.id).where(Character.server_id == server.id)
    ).all()
    session.execute(delete(Character).where(Character.server_id == server.id))
    session.execute(
        delete(SetupAssignment).where(
            SetupAssignment.artist_seat_id.in_([s.id for s in server.seats])
        )
    )
    session.delete(server)
    session.commit()
    for character_id in character_ids:
        delete_quietly(files, str(character_id))
