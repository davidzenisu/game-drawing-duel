"""Stars, the currency players collect: for writing a challenger title,
drawing a challenger and winning a fight (`rules.STARS_FOR_PROMPT`, …),
and, for its artist, a challenger's stars in every fight it won, to collect
once the fight's day is over (`challenger_stars`). Once a player's pulls
are used up, stars buy more (`buy_pull`).
Each reward is a `StarGrant` with a reason that names it, so it's never
awarded twice."""

import uuid

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import pulls
from app.models import PullGrant, StarGrant
from app.rules import STARS_PER_PULL


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


class CantBuyPull(Exception):
    pass


def buy_pull(session: Session, seat_id: uuid.UUID) -> None:
    """Spends `rules.STARS_PER_PULL` stars on a pull: only once the seat's
    pulls are used up. Each purchase is numbered, so the same one never
    counts twice. Commits."""
    if pulls.tickets(session, seat_id) > 0:
        raise CantBuyPull("Use your pulls first")
    if balance(session, seat_id) < STARS_PER_PULL:
        raise CantBuyPull(f"A pull costs {STARS_PER_PULL} stars")
    bought = session.scalar(
        select(func.count()).where(
            StarGrant.seat_id == seat_id, StarGrant.reason.like("pull:%")
        )
    )
    n = bought + 1
    session.add(grant(seat_id, f"pull:{n}", -STARS_PER_PULL))
    session.add(PullGrant(seat_id=seat_id, reason=f"stars:{n}"))
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        raise CantBuyPull("You bought that pull already") from error
