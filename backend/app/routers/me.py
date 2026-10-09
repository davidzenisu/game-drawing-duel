from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import Auth0Subject
from app.database import get_db
from app.models import Player
from app.schemas import PlayerResponse, PlayerUpdate

router = APIRouter(prefix="/me", tags=["players"])


def _find(session: Session, subject: str) -> Player | None:
    return session.scalar(select(Player).where(Player.auth0_id == subject))


@router.get("", response_model=PlayerResponse)
def get_me(
    subject: Auth0Subject,
    session: Annotated[Session, Depends(get_db)],
) -> Player:
    """The signed-in player. 404 until they finished signing up."""
    player = _find(session, subject)
    if player is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not signed up yet",
        )
    return player


@router.put("", response_model=PlayerResponse)
def put_me(
    update: PlayerUpdate,
    subject: Auth0Subject,
    session: Annotated[Session, Depends(get_db)],
) -> Player:
    """Finishes signing up by picking a first name, or changes it later.

    The first call creates the player and links it to the Auth0 account.
    """
    player = _find(session, subject)
    if player is None:
        player = Player(auth0_id=subject, first_name=update.first_name)
        session.add(player)
        try:
            session.commit()
        except IntegrityError:
            # Signed up concurrently, e.g. from two tabs: update that record.
            session.rollback()
            player = _find(session, subject)
            if player is None:
                raise
            player.first_name = update.first_name
            session.commit()
    else:
        player.first_name = update.first_name
        session.commit()
    session.refresh(player)
    return player
