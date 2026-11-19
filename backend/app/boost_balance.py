"""The boost balance: each week, the boost stars a player gives a day change
by how the fights of the week before went.

A week starts from the week before's boost stars, `rules.BOOST_STARS` in the
first week. The heroes' share of the week before's decided fights (the ones
the players who picked the fighters, or chance, won) changes them by
`rules.boost_balance_step`, within `rules.BOOST_MIN_STARS` and
`rules.BOOST_MAX_STARS`. One challenger takes all of them at most. Speed
mode sessions have no weeks, so they keep `rules.BOOST_STARS`, and so do
the weeks before `rules.BALANCE_FROM`'s: the first week on starts from it.
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

    # The first and last day of the week before, whose fights count.
    from_day: int
    to_day: int
    # Its decided fights, and how many of them the heroes won.
    fights: int
    hero_wins: int
    # Its boost stars, and the change its fights give.
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


def balance(session: Session, server: Server, day: int) -> Balance | None:
    """The boost balance of `day`'s week. The fights of the weeks before
    must be decided (`app.fights.complete_fights`,
    `app.fights.decide_fights`). None in the first week and in speed
    mode, and before `rules.BALANCE_FROM`'s week."""
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
        start = days.week_start(server, fight_day)
        fights[start] += 1
        wins[start] += fighters_win
    stars = rules.BOOST_STARS
    for start in range(first_week, week - 7, 7):
        # The weeks before the balance keep the base stars.
        if days.balanced(server, start + 7):
            stars = rules.balanced_boost_stars(
                stars, rules.boost_balance_step(wins[start], fights[start])
            )
    last = week - 7
    return Balance(
        from_day=last,
        to_day=week - 1,
        fights=fights[last],
        hero_wins=wins[last],
        previous_stars=stars,
        step=rules.boost_balance_step(wins[last], fights[last]),
    )


def stars(session: Session, server: Server, day: int) -> int:
    """The boost stars a player gives on `day`; one challenger takes all of
    them at most."""
    found = balance(session, server, day)
    return rules.BOOST_STARS if found is None else found.stars
