"""Stars, the currency players collect: for writing a challenger title,
drawing a challenger and winning a fight (`rules.STARS_FOR_PROMPT`, …),
and, for its artist, a challenger's stars in every fight it won, to collect
once the fight's day is over (`challenger_stars`).
Each reward is a `StarGrant` with a reason that names it, so it's never
awarded twice."""

import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import StarGrant


def grant(seat_id: uuid.UUID, reason: str, stars: int) -> StarGrant:
    """The grant of `stars` for `reason`, to add to the session."""
    return StarGrant(seat_id=seat_id, reason=reason, stars=stars)


def balance(session: Session, seat_id: uuid.UUID) -> int:
    """The stars the seat has."""
    return session.scalar(
        select(func.coalesce(func.sum(StarGrant.stars), 0)).where(
            StarGrant.seat_id == seat_id
        )
    )


def granted(session: Session, seat_id: uuid.UUID, reasons: list[str]) -> set[str]:
    """Which of `reasons` the seat was granted stars for already."""
    if not reasons:
        return set()
    return set(
        session.scalars(
            select(StarGrant.reason).where(
                StarGrant.seat_id == seat_id, StarGrant.reason.in_(reasons)
            )
        )
    )


def challenger_stars(record, seat_id: uuid.UUID) -> list[tuple[str, int]]:
    """The stars `seat_id` gets for its challenger of `record`
    (`fights.ChallengerRecord`): the challenger's stars in each decided fight
    it won, by reason. None for someone else's challenger."""
    if record.challenger.artist_seat_id != seat_id:
        return []
    return [(f"challenger-won:{fight.id}", stars) for fight, stars in record.won]
