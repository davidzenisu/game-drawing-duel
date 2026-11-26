"""The boost balance: each week, the boost stars a player gives a day change
by how the fights of the week before went.

A week's boost stars are the ones its challengers are boosted with: a
challenger is boosted the day before it's fought, so they start on the
Sunday before the week and end on its Saturday (`fight_week`). A week starts
from the week before's boost stars, `rules.BOOST_STARS` in the first week.
The heroes' share of the week before's decided fights from Monday to
Saturday (the ones the players who picked the fighters, or chance, won;
Sunday's aren't over when its boosts start) changes them by
`rules.boost_balance_step`, within `rules.BOOST_MIN_STARS` and
`rules.BOOST_MAX_STARS`. One challenger takes all of them at most. Speed
mode sessions have no weeks, so they keep `rules.BOOST_STARS`, and so do
the weeks before `rules.BALANCE_FROM`'s: the first week on starts from it.
The balanced weeks before `rules.BOOST_WEEK_SHIFT_FROM`'s start on their
Monday instead, from the whole week before's fights.
"""

from collections import Counter
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import days, rules, speed
from app.models import Character, Fight, Server


@dataclass(frozen=True)
class Balance:
    """The boost stars of a week, and why."""

    # The first and last day of the week before whose fights count.
    from_day: int
    to_day: int
    # Their decided fights, how many of them the heroes won, and how many it
    # takes to change the stars.
    fights: int
    hero_wins: int
    min_fights: int
    # The week before's boost stars, and the change its fights give.
    previous_stars: int
    step: int

    @property
    def stars(self) -> int:
        """The week's boost stars a day."""
        return rules.balanced_boost_stars(self.previous_stars, self.step)

    @property
    def max_per_challenger(self) -> int:
        """The most of them one challenger takes."""
        return self.stars


def _shifted(server: Server, week: int) -> bool:
    """Whether the week starting on `week` starts its boost stars on the
    Sunday before (`rules.BOOST_WEEK_SHIFT_FROM`)."""
    return days.date_of_day(server, week) >= rules.BOOST_WEEK_SHIFT_FROM


def fight_week(server: Server, day: int) -> int:
    """The first day of the week whose boost stars a player gives on `day`:
    the week the challengers boosted that day are fought in, so on Sunday
    already next week's."""
    week = days.week_start(server, day + 1)
    return week if _shifted(server, week) else days.week_start(server, day)


def next_week(server: Server, day: int) -> bool:
    """Whether the boost stars given on `day` are next week's (on Sunday)."""
    return not speed.is_speed(server) and fight_week(server, day) > days.week_start(
        server, day
    )


def _counted(server: Server, week: int) -> tuple[int, int, int]:
    """The first and last day whose fights change the boost stars of the
    week starting on `week`, and how many it takes."""
    before = week - 7
    if _shifted(server, week):
        return before, before + 5, rules.BOOST_BALANCE_MIN_FIGHTS
    return before, before + 6, rules.BOOST_BALANCE_MIN_FIGHTS_BEFORE


def week_balance(session: Session, server: Server, day: int) -> Balance | None:
    """The boost balance of `day`'s week (Monday to Sunday): the stars its
    challengers are boosted with. The counted fights of the weeks before
    must be decided (`app.fights.complete_fights`,
    `app.fights.decide_fights`). None in the first week and in speed mode,
    and before `rules.BALANCE_FROM`'s week."""
    if speed.is_speed(server) or not days.balanced(server, day):
        return None
    first_week = days.week_start(server, 1)
    week = days.week_start(server, day)
    if week <= first_week:
        return None
    results = session.execute(
        select(Fight.day, Fight.fighters_win)
        .join(Character, Character.id == Fight.challenger_id)
        .where(
            Character.server_id == server.id,
            Fight.day >= first_week,
            Fight.day < week,
            Fight.fighters_win.is_not(None),
        )
    ).all()
    fights: Counter[int] = Counter()
    wins: Counter[int] = Counter()
    for fight_day, fighters_win in results:
        fights[fight_day] += 1
        wins[fight_day] += fighters_win

    def counted(start: int) -> tuple[int, int, int, int, int]:
        first, last, min_fights = _counted(server, start)
        n = sum(fights[d] for d in range(first, last + 1))
        won = sum(wins[d] for d in range(first, last + 1))
        return first, last, n, won, min_fights

    stars = rules.BOOST_STARS
    for start in range(first_week + 7, week, 7):
        # The weeks before the balance keep the base stars.
        if days.balanced(server, start):
            _, _, n, won, min_fights = counted(start)
            stars = rules.balanced_boost_stars(
                stars, rules.boost_balance_step(won, n, min_fights)
            )
    first, last, n, won, min_fights = counted(week)
    return Balance(
        from_day=first,
        to_day=last,
        fights=n,
        hero_wins=won,
        min_fights=min_fights,
        previous_stars=stars,
        step=rules.boost_balance_step(won, n, min_fights),
    )


def balance(session: Session, server: Server, day: int) -> Balance | None:
    """The boost balance of the stars a player gives on `day`: the week's
    the challengers boosted that day are fought in (`fight_week`)."""
    if speed.is_speed(server):
        return None
    return week_balance(session, server, fight_week(server, day))


def stars(session: Session, server: Server, day: int) -> int:
    """The boost stars a player gives on `day`; one challenger takes all of
    them at most."""
    found = balance(session, server, day)
    return rules.BOOST_STARS if found is None else found.stars


def last_counted_day(server: Server, day: int) -> int | None:
    """The last day whose fights change the boost stars given on `day`; None
    in speed mode."""
    if speed.is_speed(server):
        return None
    return _counted(server, fight_week(server, day))[1]
