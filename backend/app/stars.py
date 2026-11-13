"""Stars, the currency players collect: for writing a challenger title,
drawing a challenger and winning a fight (`rules.STARS_FOR_PROMPT`, …).
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
