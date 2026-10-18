from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import CONTENT_PERMISSION, Auth0Subject, TokenClaims
from app.database import get_db
from app.models import Player, TutorialSeen
from app.schemas import MeResponse, PlayerUpdate

router = APIRouter(prefix="/me", tags=["players"])


def _find(session: Session, subject: str) -> Player | None:
    return session.scalar(select(Player).where(Player.auth0_id == subject))


def _me(session: Session, player: Player, claims: dict) -> MeResponse:
    return MeResponse(
        id=player.id,
        first_name=player.first_name,
        created_at=player.created_at,
        can_edit_content=CONTENT_PERMISSION in claims["permissions"],
        tutorials_seen=list(
            session.scalars(
                select(TutorialSeen.key)
                .where(TutorialSeen.player_id == player.id)
                .order_by(TutorialSeen.seen_at, TutorialSeen.key)
            )
        ),
    )


def _signed_up(session: Session, subject: str) -> Player:
    player = _find(session, subject)
    if player is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not signed up yet",
        )
    return player


@router.get("", response_model=MeResponse)
def get_me(
    subject: Auth0Subject,
    claims: TokenClaims,
    session: Annotated[Session, Depends(get_db)],
) -> MeResponse:
    """The signed-in player. 404 until they finished signing up."""
    return _me(session, _signed_up(session, subject), claims)


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
    return _me(session, player, claims)


TutorialKey = Annotated[str, Path(pattern=r"^[a-z0-9-]{1,40}$")]


@router.put("/tutorials/{key}", response_model=MeResponse)
def see_tutorial(
    key: TutorialKey,
    subject: Auth0Subject,
    claims: TokenClaims,
    session: Annotated[Session, Depends(get_db)],
) -> MeResponse:
    """Marks a tutorial as seen, so the app doesn't show it again on any
    device. Seeing it again changes nothing."""
    player = _signed_up(session, subject)
    try:
        with session.begin_nested():
            session.add(TutorialSeen(player_id=player.id, key=key))
    except IntegrityError:
        pass  # Seen already, maybe at the same time on another device.
    session.commit()
    return _me(session, player, claims)
