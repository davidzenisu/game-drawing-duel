"""Player stats: how every player did in a week, a category at a time, each
a full ranking of the players (`ranking`). The week ranking shows them for
the ongoing week and the last finished one. Once a week is over, the first
place of each category wins a trophy (`Trophy`), worth
`rules.STARS_FOR_WEEK_STAT` stars as a gift to accept (`award`); tied first
places each win one. Speed mode sessions have none.

- `most-wins` (Giant Slayer): the fights won, of the ones they picked the fighters for
  (chance's don't count, as everywhere).
- `most-boosted` (Grand Artist): the boost stars the challengers they drew got, counted in
  the week of their fight (as the week ranking), so a ranking never gives
  away a challenger that isn't fought yet. Secret during the ongoing week
  (`SECRET`): it would tell how strong a drawing is.
- `busy-streak` (Addict): the run of days up to the week's last one, across weeks,
  on which they did every daily step they could themselves: their title,
  drawing, boosts and fight (`_did_all`). A step with nothing to do doesn't
  break it. In the ongoing week, today counts once it's done, and doesn't
  break it before.
"""

import uuid
from collections import defaultdict
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import days, fights, pulls, rules
from app.models import (
    Boost,
    ChallengerPrompt,
    Character,
    Fight,
    Gift,
    GiftDelivery,
    Server,
    ServerSeat,
    Trophy,
)

STATS = ("most-wins", "most-boosted", "busy-streak")

# Hidden during the ongoing week.
SECRET = frozenset({"most-boosted"})

NAMES = {
    "most-wins": "Giant Slayer",
    "most-boosted": "Grand Artist",
    "busy-streak": "Addict",
}

# A challenger is fought this many days after it was drawn.
_FIGHT_AFTER_DRAWING = days.FIGHT_DAY_OFFSET - 1


@dataclass(frozen=True)
class Placed:
    seat: ServerSeat
    value: int
    # 1 for the first; tied players share a place, the next skips theirs.
    place: int


@dataclass(frozen=True)
class _Done:
    """The daily steps players did themselves, as (seat, day) pairs."""

    prompts: set[tuple[uuid.UUID, int]]
    drawings: set[tuple[uuid.UUID, int]]
    boosts: set[tuple[uuid.UUID, int]]
    fights: set[tuple[uuid.UUID, int]]


def _done(session: Session, server: Server) -> _Done:
    seats = [s.id for s in server.seats]
    return _Done(
        prompts={
            tuple(row)
            for row in session.execute(
                select(ChallengerPrompt.author_seat_id, ChallengerPrompt.day).where(
                    ChallengerPrompt.author_seat_id.in_(seats)
                )
            )
        },
        drawings={
            tuple(row)
            for row in session.execute(
                select(Character.artist_seat_id, Character.day).where(
                    Character.server_id == server.id,
                    Character.assignment_id.is_(None),
                )
            )
        },
        boosts={
            tuple(row)
            for row in session.execute(
                select(Boost.booster_seat_id, Boost.day).where(
                    Boost.booster_seat_id.in_(seats),
                    Boost.by_chance.is_(False),
                    Boost.stars > 0,
                )
            )
        },
        fights={
            tuple(row)
            for row in session.execute(
                select(Fight.owner_seat_id, Fight.day).where(
                    Fight.owner_seat_id.in_(seats), Fight.by_chance.is_(False)
                )
            )
        },
    )


def _did_all(
    session: Session, server: Server, seat: ServerSeat, day: int, done: _Done
) -> bool:
    """Whether `seat` did every step of `day` they could themselves. What's
    done is looked up first: whether there was anything to do only matters
    for what wasn't."""
    key = (seat.id, day)
    if key not in done.prompts and days.prompts_on(server, day):
        return False
    if (
        key not in done.drawings
        and days.prompt_to_draw(session, server, day, seat) is not None
    ):
        return False
    if key not in done.boosts and fights.boost_targets(session, server, day, seat):
        return False
    if key not in done.fights and fights.fight_challenger(session, server, day, seat):
        available = set(pulls.copies(session, seat)) - set(
            fights.resting(session, server, seat, day)
        )
        if available:
            return False
    return True


def _busy_streak(
    session: Session,
    server: Server,
    seat: ServerSeat,
    last: int,
    done: _Done,
    today: int,
) -> int:
    streak = 0
    day = last
    if day == today and not _did_all(session, server, seat, day, done):
        day -= 1  # Today isn't over: it only counts once it's done.
    while day >= 1 and _did_all(session, server, seat, day, done):
        streak += 1
        day -= 1
    return streak


def values(
    session: Session, server: Server, first: int, last: int
) -> dict[str, dict[uuid.UUID, int]]:
    """Every stat of every seat that joined, from day `first` to day `last`
    (the Addict streak up to `last`)."""
    seats = days.active_seats(server)
    ids = [s.id for s in seats]
    stats: dict[str, dict[uuid.UUID, int]] = {
        stat: dict.fromkeys(ids, 0) for stat in STATS
    }

    for seat_id, won in session.execute(
        select(Fight.owner_seat_id, func.count())
        .where(
            Fight.owner_seat_id.in_(ids),
            Fight.day >= first,
            Fight.day <= last,
            Fight.by_chance.is_(False),
            Fight.fighters_win.is_(True),
        )
        .group_by(Fight.owner_seat_id)
    ):
        stats["most-wins"][seat_id] = won

    for seat_id, boosted in session.execute(
        select(Character.artist_seat_id, func.sum(Boost.stars))
        .join(Boost, Boost.challenger_id == Character.id)
        .where(
            Character.server_id == server.id,
            Character.assignment_id.is_(None),
            Character.day >= first - _FIGHT_AFTER_DRAWING,
            Character.day <= last - _FIGHT_AFTER_DRAWING,
        )
        .group_by(Character.artist_seat_id)
    ):
        if seat_id in stats["most-boosted"]:
            stats["most-boosted"][seat_id] = boosted or 0

    done = _done(session, server)
    today = days.current_day(server)
    for seat in seats:
        stats["busy-streak"][seat.id] = _busy_streak(
            session, server, seat, last, done, today
        )
    return stats


def portrayed(session: Session, server: Server, week_end: int) -> dict[uuid.UUID, int]:
    """How many of the challengers the week ending on `week_end` ranks
    (fought that week, as `app.finale.ranking`) portray each seat, of the
    ones drawn so far."""
    first = days.week_start(server, week_end)
    return dict(
        session.execute(
            select(Character.subject_seat_id, func.count())
            .where(
                Character.server_id == server.id,
                Character.assignment_id.is_(None),
                Character.day >= first - _FIGHT_AFTER_DRAWING,
                Character.day <= week_end - _FIGHT_AFTER_DRAWING,
            )
            .group_by(Character.subject_seat_id)
        ).all()
    )


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


def week_number(server: Server, day: int) -> int:
    """The week `day` falls in: week 1 is the launch week (Monday to Sunday,
    so it may be short)."""
    return (days.week_start(server, day) - days.week_start(server, 1)) // 7 + 1


def award(session: Session, server: Server, day: int) -> list[Trophy | Gift]:
    """The trophies of the week that ends on `day`, and the gifts of their
    stars, to add to the session."""
    stats = values(session, server, days.week_start(server, day), day)
    awarded: list[Trophy | Gift] = []
    for stat in STATS:
        winners = first_places(server, stats[stat])
        if not winners:
            continue
        awarded.extend(Trophy(seat_id=s.id, stat=stat, day=day) for s in winners)
        awarded.append(
            Gift(
                message=f"Trophy: {NAMES[stat]} in week {week_number(server, day)}!",
                pulls=0,
                stars=rules.STARS_FOR_WEEK_STAT,
                server_id=server.id,
                deliveries=[GiftDelivery(seat_id=seat.id) for seat in winners],
            )
        )
    return awarded


def trophies(session: Session, server: Server) -> dict[str, dict[uuid.UUID, int]]:
    """How many trophies each seat won so far, by stat."""
    counts: dict[str, dict[uuid.UUID, int]] = defaultdict(dict)
    for seat_id, stat, won in session.execute(
        select(Trophy.seat_id, Trophy.stat, func.count())
        .where(Trophy.seat_id.in_([s.id for s in server.seats]))
        .group_by(Trophy.seat_id, Trophy.stat)
    ):
        counts[stat][seat_id] = won
    return counts
