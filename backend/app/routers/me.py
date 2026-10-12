from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import CONTENT_PERMISSION, Auth0Subject, TokenClaims
from app.database import get_db
from app.models import Player
from app.schemas import MeResponse, PlayerUpdate

router = APIRouter(prefix="/me", tags=["players"])


def _find(session: Session, subject: str) -> Player | None:
    return session.scalar(select(Player).where(Player.auth0_id == subject))


def _me(player: Player, claims: dict) -> MeResponse:
    return MeResponse(
        id=player.id,
        first_name=player.first_name,
        created_at=player.created_at,
        can_edit_content=CONTENT_PERMISSION in claims["permissions"],
    )


@router.get("", response_model=MeResponse)
def get_me(
    subject: Auth0Subject,
    claims: TokenClaims,
    session: Annotated[Session, Depends(get_db)],
) -> MeResponse:
    """The signed-in player. 404 until they finished signing up."""
    player = _find(session, subject)
    if player is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not signed up yet",
        )
    return _me(player, claims)


@router.put("", response_model=MeResponse)
def put_me(
    update: PlayerUpdate,
    subject: Auth0Subject,
    claims: TokenClaims,
    session: Annotated[Session, Depends(get_db)],
) -> MeResponse:
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
    return _me(player, claims)
