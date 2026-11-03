"""What the routers share: path and session parameters, and loading the
server and your seat in it."""

import uuid
from typing import Annotated

from fastapi import Depends, HTTPException, Path, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.models import Server, ServerSeat
from app.rules import SERVER_CODE_LENGTH
from app.setup import launch_if_due

Code = Annotated[str, Path(pattern=rf"^\d{{{SERVER_CODE_LENGTH}}}$")]
DbSession = Annotated[Session, Depends(get_db)]


def load_server(session: Session, code: str, *, cancelled_ok: bool = False) -> Server:
    """The server with `code`; `410 Gone` once it was cancelled, unless
    `cancelled_ok`."""
    server = session.scalar(
        select(Server).where(Server.code == code).options(selectinload(Server.seats))
    )
    if server is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="No server with this code"
        )
    if server.cancelled_at is not None and not cancelled_ok:
        raise HTTPException(status.HTTP_410_GONE, detail="The server was cancelled")
    if server.cancelled_at is None:
        launch_if_due(session, server)
    return server


def your_seat(server: Server, player_id: uuid.UUID) -> ServerSeat:
    seat = next((s for s in server.seats if s.player_id == player_id), None)
    if seat is None:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, detail="You haven't joined this server"
        )
    return seat


def require_launched(server: Server) -> None:
    if server.launched_at is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="The game hasn't launched yet"
        )


def running_game(
    session: Session, code: str, player_id: uuid.UUID
) -> tuple[Server, ServerSeat]:
    """The launched server with `code` and your seat in it."""
    server = load_server(session, code)
    seat = your_seat(server, player_id)
    require_launched(server)
    return server, seat


def require_not_launched(server: Server) -> None:
    if server.launched_at is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="The game already launched"
        )
