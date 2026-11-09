"""Gifts waiting for you on a server, to accept (`app.gifts`)."""

import uuid

from fastapi import APIRouter, HTTPException, status

from app import gifts
from app.auth import CurrentPlayer
from app.deps import Code, DbSession, running_game
from app.models import Gift
from app.schemas import GiftResponse

router = APIRouter(prefix="/servers", tags=["gifts"])


def _response(gift: Gift) -> GiftResponse:
    return GiftResponse(
        id=gift.id, message=gift.message, pulls=gift.pulls, sent_at=gift.sent_at
    )


@router.get("/{code}/gifts", response_model=list[GiftResponse])
def get_gifts(
    code: Code, player: CurrentPlayer, session: DbSession
) -> list[GiftResponse]:
    """The gifts waiting for you, oldest first; their pulls count once you
    accept them. The app shows them on its notification board."""
    _, seat = running_game(session, code, player.id)
    return [_response(g) for g in gifts.pending(session, seat)]


@router.post("/{code}/gifts/{gift_id}/accept", response_model=list[GiftResponse])
def accept_gift(
    code: Code, gift_id: uuid.UUID, player: CurrentPlayer, session: DbSession
) -> list[GiftResponse]:
    """Accepts a gift: its pulls are yours now. Returns the gifts still
    waiting. Accepting one again changes nothing."""
    _, seat = running_game(session, code, player.id)
    try:
        gifts.accept(session, seat, gift_id)
    except gifts.GiftError as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=str(error)) from error
    return [_response(g) for g in gifts.pending(session, seat)]
