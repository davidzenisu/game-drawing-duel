"""The characters of a running game: the pool, pulls and your collection."""

import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app import pulls, upgrades
from app.auth import CurrentPlayer
from app.models import Character, Server, ServerSeat
from app.routers.servers import Code, DbSession, load_server, your_seat
from app.routers.setup import character_response
from app.schemas import (
    CharacterResponse,
    GachaResponse,
    OwnedCharacterResponse,
    PullOutcomeResponse,
    PullRequest,
    PullsResponse,
    UpgradeRequest,
)

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
        .order_by(Character.created_at)
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


def _gacha(session: Session, seat: ServerSeat) -> GachaResponse:
    state = pulls.gacha_state(session, seat.id)
    return GachaResponse(
        tickets=pulls.tickets(session, seat.id),
        total_pulls=state.total_pulls,
        pulls_until_legend=state.pulls_until_legend,
        beginner_pulls_left=state.beginner_pulls_left,
    )


def _running_seat(session: Session, code: str, player_id: uuid.UUID) -> ServerSeat:
    server = load_server(session, code)
    seat = your_seat(server, player_id)
    _launched(server)
    return seat


@router.get("/{code}/gacha", response_model=GachaResponse)
def get_gacha(code: Code, player: CurrentPlayer, session: DbSession) -> GachaResponse:
    """Your pulls left and pity progress."""
    return _gacha(session, _running_seat(session, code, player.id))


@router.post("/{code}/pulls", response_model=PullsResponse)
def pull(
    code: Code, body: PullRequest, player: CurrentPlayer, session: DbSession
) -> PullsResponse:
    """Spends pulls on random characters of the pool, see `app/gacha.py`."""
    seat = _running_seat(session, code, player.id)
    try:
        outcomes = pulls.pull(session, seat, body.count)
    except pulls.NotEnoughPulls as error:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="Not enough pulls"
        ) from error
    session.commit()
    return PullsResponse(
        outcomes=[
            PullOutcomeResponse(
                character=character_response(o.character),
                is_new=o.is_new,
                copies=o.copies,
            )
            for o in outcomes
        ],
        gacha=_gacha(session, seat),
    )


@router.get("/{code}/collection", response_model=list[OwnedCharacterResponse])
def get_collection(
    code: Code, player: CurrentPlayer, session: DbSession
) -> list[OwnedCharacterResponse]:
    """Your characters: the ones you drew during the setup and the ones you
    pulled, with how many copies you own."""
    seat = _running_seat(session, code, player.id)
    return _collection(session, seat)


def _collection(
    session: Session, seat: ServerSeat, *ids: uuid.UUID
) -> list[OwnedCharacterResponse]:
    """The seat's characters, or only those with `ids`."""
    owned = pulls.copies(session, seat)
    done = upgrades.unlocked(session, seat.id)
    characters = session.scalars(
        select(Character)
        .where(Character.id.in_(ids or owned))
        .options(selectinload(Character.artist), selectinload(Character.subject))
        .order_by(Character.created_at)
    )
    return [
        OwnedCharacterResponse(
            character=character_response(c),
            copies=owned[c.id],
            upgrades=[e.value for e in done[c.id].effects],
            element=done[c.id].element,
        )
        for c in characters
    ]


@router.post(
    "/{code}/collection/{character_id}/upgrades", response_model=OwnedCharacterResponse
)
def unlock_upgrade(
    code: Code,
    character_id: uuid.UUID,
    body: UpgradeRequest,
    player: CurrentPlayer,
    session: DbSession,
) -> OwnedCharacterResponse:
    """Spends a duplicate on the character's next upgrade."""
    seat = _running_seat(session, code, player.id)
    character = session.get(Character, character_id)
    if character is None or character.server_id != seat.server_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such character")
    try:
        upgrades.unlock_next(session, seat, character, body.element)
    except upgrades.ElementRequired as error:
        session.rollback()
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(error)
        ) from error
    except upgrades.UpgradeRejected as error:
        session.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, detail=str(error)) from error
    session.commit()
    return _collection(session, seat, character.id)[0]
