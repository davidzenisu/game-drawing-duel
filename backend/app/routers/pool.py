"""The characters of a running game."""

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.auth import CurrentPlayer
from app.models import Character, Server
from app.routers.servers import Code, DbSession, load_server, your_seat
from app.routers.setup import character_response
from app.schemas import CharacterResponse

router = APIRouter(prefix="/servers", tags=["pool"])


def _launched(server: Server) -> None:
    if server.launched_at is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="The game hasn't launched yet"
        )


def _characters(session: DbSession, *conditions) -> list[CharacterResponse]:
    characters = session.scalars(
        select(Character)
        .where(*conditions)
        .options(selectinload(Character.artist), selectinload(Character.subject))
        .order_by(Character.created_at, Character.id)
    )
    return [character_response(c) for c in characters]


@router.get("/{code}/pool", response_model=list[CharacterResponse])
def get_pool(
    code: Code, player: CurrentPlayer, session: DbSession
) -> list[CharacterResponse]:
    """Every character of the game, which the gacha pulls from."""
    server = load_server(session, code)
    your_seat(server, player.id)
    _launched(server)
    return _characters(session, Character.server_id == server.id)


@router.get("/{code}/collection", response_model=list[CharacterResponse])
def get_collection(
    code: Code, player: CurrentPlayer, session: DbSession
) -> list[CharacterResponse]:
    """Your characters: so far the ones you drew during the setup."""
    server = load_server(session, code)
    seat = your_seat(server, player.id)
    _launched(server)
    return _characters(
        session, Character.server_id == server.id, Character.artist_seat_id == seat.id
    )
