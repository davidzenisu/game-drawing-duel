"""Player stats: how every player did over a span of days, a stat at a time,
each a full ranking of the players (`ranking`). The week ranking shows them
for the ongoing week, the last finished one and all time; once a week is
over, the first place of each stat gets `rules.STARS_FOR_WEEK_STAT` stars
as a gift to accept (`rewards`), tied first places all of them. Speed mode
sessions have none.

- `stars-earned`: the stars a player earned, spent ones too: for prompts,
  drawings, wins, their challengers' wins and achievements; not gifts. A
  reward counts on the day it was earned: the day in its reason, else the
  day it was granted on.
- `hot-streak`: the most fights won in a row, of the ones they picked the
  fighters for; a lost one starts over (as the streak achievements).
- `most-wins`: the fights won, of the ones they picked the fighters for.
- `best-artist`: the stars of the challengers they drew, in the week of
  their fight (as the week ranking).
- `giant-slayer`: the stars of the challengers they beat, added up.
- `most-boosts`: the boost stars they gave themselves.
- `busiest`: the daily steps they did themselves: titles written,
  challengers drawn, days they boosted and fights they picked.
"""

import re
import uuid
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app import days, fights, rules
from app.models import (
    Boost,
    ChallengerPrompt,
    Character,
    Fight,
    Gift,
    GiftDelivery,
    Server,
    ServerSeat,
    StarGrant,
)

STATS = (
    "stars-earned",
    "hot-streak",
    "most-wins",
    "best-artist",
    "giant-slayer",
    "most-boosts",
    "busiest",
)

NAMES = {
    "stars-earned": "Stars earned",
    "hot-streak": "Hot streak",
    "most-wins": "Most wins",
    "best-artist": "Best artist",
    "giant-slayer": "Giant slayer",
    "most-boosts": "Most boosts",
    "busiest": "Busiest",
}

# A challenger is fought this many days after it was drawn.
_FIGHT_AFTER_DRAWING = days.FIGHT_DAY_OFFSET - 1

# The rewards whose reason names their day.
_DAY_REASON = re.compile(r"^(?:prompt|challenger|fight):day-(\d+)(?::|$)")


@dataclass(frozen=True)
class Placed:
    seat: ServerSeat
    value: int
    # 1 for the first; tied players share a place, the next skips theirs.
    place: int


def _grant_day(server: Server, grant: StarGrant) -> int:
    """The day of the game a star reward counts for."""
    if match := _DAY_REASON.match(grant.reason):
        return int(match.group(1))
    granted = grant.granted_at
    if granted.tzinfo is None:  # SQLite drops the time zone.
        granted = granted.replace(tzinfo=UTC)
    return (granted.astimezone(UTC).date() - days.date_of_day(server, 1)).days + 1


def values(
    session: Session, server: Server, first: int, last: int
) -> dict[str, dict[uuid.UUID, int]]:
    """Every stat of every seat, from day `first` to day `last`."""
    seats = [s.id for s in server.seats]
    stats: dict[str, dict[uuid.UUID, int]] = {
        stat: dict.fromkeys(seats, 0) for stat in STATS
    }

    for grant in session.scalars(
        select(StarGrant).where(
            StarGrant.seat_id.in_(seats),
            StarGrant.stars > 0,
            StarGrant.reason.not_like("gift:%"),
        )
    ):
        if first <= _grant_day(server, grant) <= last:
            stats["stars-earned"][grant.seat_id] += grant.stars

    picked = session.scalars(
        select(Fight)
        .where(
            Fight.owner_seat_id.in_(seats),
            Fight.day >= first,
            Fight.day <= last,
            Fight.by_chance.is_(False),
        )
        .order_by(Fight.day)
        .options(selectinload(Fight.fighters))
    ).all()
    streaks: dict[uuid.UUID, int] = defaultdict(int)
    for fight in picked:
        result = fights.outcome(session, fight)
        seat = fight.owner_seat_id
        stats["busiest"][seat] += 1
        if not result.fighters_win:
            streaks[seat] = 0
            continue
        streaks[seat] += 1
        stats["hot-streak"][seat] = max(stats["hot-streak"][seat], streaks[seat])
        stats["most-wins"][seat] += 1
        stats["giant-slayer"][seat] += result.challenger_stars

    for challenger in session.scalars(
        select(Character).where(
            Character.server_id == server.id,
            Character.assignment_id.is_(None),
            Character.day >= first - _FIGHT_AFTER_DRAWING,
            Character.day <= last,
        )
    ):
        if challenger.day >= first:
            stats["busiest"][challenger.artist_seat_id] += 1
        if challenger.day + _FIGHT_AFTER_DRAWING <= last:
            stats["best-artist"][challenger.artist_seat_id] += rules.challenger_stars(
                fights.boost_stars(session, challenger.id)
            )

    boost_days: set[tuple[uuid.UUID, int]] = set()
    for boost in session.scalars(
        select(Boost).where(
            Boost.booster_seat_id.in_(seats),
            Boost.day >= first,
            Boost.day <= last,
            Boost.by_chance.is_(False),
        )
    ):
        stats["most-boosts"][boost.booster_seat_id] += boost.stars
        if boost.stars > 0:
            boost_days.add((boost.booster_seat_id, boost.day))
    for seat, _ in boost_days:
        stats["busiest"][seat] += 1

    for author in session.scalars(
        select(ChallengerPrompt.author_seat_id).where(
            ChallengerPrompt.author_seat_id.in_(seats),
            ChallengerPrompt.day >= first,
            ChallengerPrompt.day <= last,
        )
    ):
        stats["busiest"][author] += 1
    return stats


def ranking(server: Server, by_seat: dict[uuid.UUID, int]) -> list[Placed]:
    """The players who joined, best first (then in roster order), with their
    place: tied players share one."""
    seats = sorted(
        days.active_seats(server), key=lambda s: (-by_seat.get(s.id, 0), s.position)
    )
    placed: list[Placed] = []
    for i, seat in enumerate(seats):
        value = by_seat.get(seat.id, 0)
        place = placed[-1].place if placed and placed[-1].value == value else i + 1
        placed.append(Placed(seat, value, place))
    return placed


def first_places(server: Server, by_seat: dict[uuid.UUID, int]) -> list[ServerSeat]:
    """The players who share the first place, none if it's 0."""
    return [p.seat for p in ranking(server, by_seat) if p.place == 1 and p.value > 0]


def rewards(session: Session, server: Server, day: int) -> list[Gift]:
    """The gifts for the first places of each stat in the week that ends on
    `day`, to add to the session."""
    stats = values(session, server, days.week_start(server, day), day)
    gifts = []
    for stat in STATS:
        winners = first_places(server, stats[stat])
        if not winners:
            continue
        gifts.append(
            Gift(
                message=f"First place in {NAMES[stat]} in the week up to day {day}!",
                pulls=0,
                stars=rules.STARS_FOR_WEEK_STAT,
                server_id=server.id,
                deliveries=[GiftDelivery(seat_id=seat.id) for seat in winners],
            )
        )
    return gifts
