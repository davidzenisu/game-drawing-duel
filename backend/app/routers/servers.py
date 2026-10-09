import secrets
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, status
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.auth import CurrentPlayer
from app.database import get_db
from app.models import Player, Server, ServerSeat, SetupAssignment
from app.rules import SERVER_CODE_LENGTH, SetupPrompt
from app.schemas import (
    AssignmentResponse,
    SeatResponse,
    ServerCreate,
    ServerResponse,
)
from app.setup import assign_setup

router = APIRouter(prefix="/servers", tags=["servers"])

Code = Annotated[str, Path(pattern=rf"^\d{{{SERVER_CODE_LENGTH}}}$")]
DbSession = Annotated[Session, Depends(get_db)]

# Retries when a random code is already taken.
_CODE_ATTEMPTS = 10


def _new_code() -> str:
    return "".join(str(secrets.randbelow(10)) for _ in range(SERVER_CODE_LENGTH))


def _response(server: Server, player: Player) -> ServerResponse:
    your_seat = next((s for s in server.seats if s.player_id == player.id), None)
    return ServerResponse(
        code=server.code,
        created_at=server.created_at,
        is_test=server.is_test,
        is_admin=server.admin_id == player.id,
        phase="lobby" if server.setup_started_at is None else "setup",
        your_position=your_seat.position if your_seat else None,
        seats=[
            SeatResponse(position=s.position, name=s.name, joined=s.player_id is not None)
            for s in server.seats
        ],
    )


def _load(session: Session, code: str) -> Server:
    server = session.scalar(
        select(Server).where(Server.code == code).options(selectinload(Server.seats))
    )
    if server is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No server with this code")
    return server


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
        return _response(_load(session, server.code), player)
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
    return [_response(server, player) for server in servers]


@router.get("/{code}", response_model=ServerResponse)
def get_server(code: Code, player: CurrentPlayer, session: DbSession) -> ServerResponse:
    """The roster and who joined. Knowing the code is the invitation."""
    return _response(_load(session, code), player)


@router.post("/{code}/seats/{position}/claim", response_model=ServerResponse)
def claim_seat(
    code: Code,
    position: Annotated[int, Path(ge=0)],
    player: CurrentPlayer,
    session: DbSession,
) -> ServerResponse:
    """Joins the server as the player the admin listed at `position`."""
    server = _load(session, code)
    seat = next((s for s in server.seats if s.position == position), None)
    if seat is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such seat")
    current = next((s for s in server.seats if s.player_id == player.id), None)
    if current is not None:
        if current.position == position:
            return _response(server, player)
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
    return _response(_load(session, code), player)


@router.post("/{code}/setup", response_model=ServerResponse)
def start_setup(
    code: Code, player: CurrentPlayer, session: DbSession
) -> ServerResponse:
    """Starts the initial drawing setup for everyone. Admin only.

    Regular servers start once everyone joined; test sessions start with the
    players who joined so far.
    """
    server = _load(session, code)
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
    return _response(_load(session, code), player)


@router.get("/{code}/assignments", response_model=list[AssignmentResponse])
def my_assignments(
    code: Code, player: CurrentPlayer, session: DbSession
) -> list[AssignmentResponse]:
    """Your drawings for the initial setup."""
    server = _load(session, code)
    seat = next((s for s in server.seats if s.player_id == player.id), None)
    if seat is None:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, detail="You haven't joined this server"
        )
    if server.setup_started_at is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="The setup hasn't started yet"
        )
    assignments = session.scalars(
        select(SetupAssignment)
        .where(SetupAssignment.artist_seat_id == seat.id)
        .options(selectinload(SetupAssignment.subject))
    ).all()
    # Every setup plan follows the order of the prompts.
    order = list(SetupPrompt)
    assignments = sorted(assignments, key=lambda a: order.index(SetupPrompt(a.prompt)))
    return [
        AssignmentResponse(
            id=a.id,
            prompt=a.prompt,
            subject_position=a.subject.position,
            based_on=a.based_on_id,
        )
        for a in assignments
    ]
