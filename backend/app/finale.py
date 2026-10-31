"""Once a week, the finale: the week's challengers ranked by their stars.

A challenger counts for the week of its boosting day, the day after it was
drawn, so its stars are final once the week is over: its own 3 plus the
boost stars it got. Every challenger is ranked; once the week is over, the
one with the most stars (then the most fights won, then the one drawn
first) joins the server's gacha pool as a hero, and everyone can see the
ranking.
"""

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app import days, fights, rules
from app.models import Character, Fight, Server, WeeklyHero


def finale_day(server: Server, day: int) -> int:
    """The last day of `day`'s week (Sunday, UTC), the day of its finale."""
    return days.week_start(server, day) + 6


@dataclass(frozen=True)
class Ranked:
    challenger: Character
    # Its own stars plus its boost stars.
    stars: int
    # Its fights by the end of the week, and how many of them it won.
    fights: int
    wins: int


def ranking(session: Session, server: Server, day: int) -> list[Ranked]:
    """The challengers of the week that ends on `day`, its last day, most
    stars first: the ones boosted that week. Their boosts must be complete
    (`app.fights.complete_boosts`)."""
    challengers = session.scalars(
        select(Character)
        .where(
            Character.server_id == server.id,
            Character.assignment_id.is_(None),
            # Boosted the day after they were drawn.
            Character.day >= day - 7,
            Character.day <= day - 1,
        )
        .options(selectinload(Character.artist), selectinload(Character.subject))
    ).all()
    entries = []
    for challenger in challengers:
        against = session.scalars(
            select(Fight)
            .where(Fight.challenger_id == challenger.id, Fight.day <= day)
            .options(selectinload(Fight.fighters))
        ).all()
        wins = sum(not fights.outcome(session, f).fighters_win for f in against)
        stars = rules.challenger_stars(fights.boost_stars(session, challenger.id))
        entries.append(Ranked(challenger, stars, len(against), wins))
    return sorted(
        entries,
        key=lambda r: (
            -r.stars,
            -r.wins,
            r.challenger.day,
            r.challenger.created_at,
            str(r.challenger.id),
        ),
    )


def _decide(session: Session, server: Server, day: int) -> WeeklyHero:
    """The finale's result: the top of the week's ranking, if any."""
    ranked = ranking(session, server, day)
    if not ranked:
        return WeeklyHero(server_id=server.id, day=day)
    top = ranked[0]
    return WeeklyHero(
        server_id=server.id, day=day, character_id=top.challenger.id, stars=top.stars
    )


def settle(session: Session, server: Server) -> None:
    """Decides every finale that's over and isn't yet. Commits."""
    today = days.current_day(server)
    decided = set(
        session.scalars(select(WeeklyHero.day).where(WeeklyHero.server_id == server.id))
    )
    day = finale_day(server, 1)
    heroes = []
    while day < today:
        if day not in decided:
            # The boost stars nobody gave on the last day count too.
            fights.complete_boosts(session, server, day)
            heroes.append(_decide(session, server, day))
        day += 7
    if not heroes:
        return
    session.add_all(heroes)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()  # Someone else decided it at the same time.


def latest_finale(session: Session, server: Server) -> WeeklyHero | None:
    """The latest decided finale, with or without a hero."""
    return session.scalar(
        select(WeeklyHero)
        .where(WeeklyHero.server_id == server.id)
        .order_by(WeeklyHero.day.desc())
        .limit(1)
        .options(selectinload(WeeklyHero.character))
    )


def latest_hero(session: Session, server: Server) -> WeeklyHero | None:
    """The hero of the latest decided finale, if it had one."""
    hero = latest_finale(session, server)
    return hero if hero is not None and hero.character_id is not None else None
