"""Once a week, the finale: the week's challengers ranked by their stars.

A challenger counts for the week of its fight, once its whole lifecycle
is through: title, drawing the day after, boosting the next day and the
fight the day after that, two days after it was drawn. A challenger titled
on a Monday is fought on Thursday and ranks that week; one titled on a
Friday is fought on Monday and ranks the next. Its stars are final by its
fight: its own 3 plus the boost stars it got. Every challenger is ranked,
by its stars, then its win rate, and everyone can see the ranking.

Once the week is over, up to `rules.FINALE_MAX_HEROES` of them are crowned
weekly heroes and join the server's gacha pool, each with a rarity by its
share of the week's maximum stars (`rules.finale_heroes`): its own stars
plus the most its boosters could give it.
"""

import random
import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app import boost_balance, days, fights, player_stats, rules, speed
from app.models import Character, Fight, Server, WeeklyHero

# A challenger is fought this many days after it was drawn (its prompt is
# written the day before): boosted the day after, fought the day after that.
FIGHT_AFTER_DRAWING = days.FIGHT_DAY_OFFSET - 1


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
    # Those fights: the seat that fought it, and whether it won.
    against: tuple[tuple[uuid.UUID, bool], ...] = ()

    @property
    def win_rate(self) -> float:
        """Its fights won out of its fights; 0 without any."""
        return self.wins / self.fights if self.fights else 0.0


def ranking(session: Session, server: Server, day: int) -> list[Ranked]:
    """The challengers of the week that ends on `day`, its last day, most
    stars first: the ones fought that week. Their boosts and fights must be
    complete (`app.fights.complete_boosts`, `app.fights.complete_fights`)."""
    challengers = session.scalars(
        select(Character)
        .where(
            Character.server_id == server.id,
            Character.assignment_id.is_(None),
            # Fought two days after they were drawn.
            Character.day >= day - 6 - FIGHT_AFTER_DRAWING,
            Character.day <= day - FIGHT_AFTER_DRAWING,
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
        won = [
            (f.owner_seat_id, not fights.outcome(session, f).fighters_win)
            for f in against
        ]
        wins = sum(w for _, w in won)
        stars = rules.challenger_stars(fights.boost_stars(session, challenger.id))
        entries.append(Ranked(challenger, stars, len(against), wins, tuple(won)))
    return sorted(
        entries,
        key=lambda r: (
            -r.stars,
            -r.win_rate,
            r.challenger.day,
            r.challenger.created_at,
            str(r.challenger.id),
        ),
    )


def places(ranked: list[Ranked]) -> list[int]:
    """Each ranked challenger's place: challengers with the same stars and
    win rate share theirs."""
    keys = [(r.stars, r.win_rate) for r in ranked]
    return [1 + sum(other > key for other in keys) for key in keys]


def heroes_of(
    session: Session, server: Server, day: int
) -> dict[uuid.UUID, WeeklyHero]:
    """The heroes the finale of `day` crowned, by character."""
    return {
        h.character_id: h
        for h in session.scalars(
            select(WeeklyHero).where(
                WeeklyHero.server_id == server.id,
                WeeklyHero.day == day,
                WeeklyHero.character_id.is_not(None),
            )
        )
    }


def max_stars(session: Session, server: Server, day: int) -> int:
    """The most stars a challenger can have in the week that ends on `day`:
    its own plus the week's boost stars from each of its boosters, as many
    as a player boosts challengers a day (fewer in a test session with
    fewer players: nobody boosts the one they drew or fight)."""
    boosters = max(0, min(rules.BOOST_CHALLENGERS, len(days.active_seats(server)) - 2))
    return rules.finale_max_stars(boost_balance.stars(session, server, day), boosters)


def _decide(session: Session, server: Server, day: int) -> list[WeeklyHero]:
    """The finale's result: its weekly heroes, or one row without a
    character if it has none. Each hero's character takes the rarity it's
    crowned with."""
    ranked = ranking(session, server, day)
    crowned = rules.finale_heroes(
        [(r.stars, r.wins, r.fights) for r in ranked], max_stars(session, server, day)
    )
    heroes = [
        (r, *hero) for r, hero in zip(ranked, crowned, strict=True) if hero is not None
    ]
    if not heroes:
        return [WeeklyHero(server_id=server.id, day=day)]
    legend = None
    if all(rarity is not rules.Rarity.LEGEND for _, _, rarity in heroes):
        legend = _rate_up_legend(
            session, server, day, [r for r, place, _ in heroes if place == 1]
        )
    rows = []
    for r, place, rarity in heroes:
        r.challenger.rarity = rarity.value
        rows.append(
            WeeklyHero(
                server_id=server.id,
                day=day,
                character_id=r.challenger.id,
                stars=r.stars,
                place=place,
                rarity=rarity.value,
                legend_id=legend,
            )
        )
    return rows


def _rate_up_legend(
    session: Session, server: Server, day: int, first: list[Ranked]
) -> uuid.UUID | None:
    """A starter legend (a legend of the setup) portraying the player of one
    of the 1st places, picked at random once per finale; None if they have
    none."""
    subjects = {r.challenger.subject_seat_id for r in first}
    legends = session.scalars(
        select(Character.id)
        .where(
            Character.server_id == server.id,
            Character.assignment_id.is_not(None),
            Character.rarity == rules.Rarity.LEGEND.value,
            Character.subject_seat_id.in_(subjects),
        )
        .order_by(Character.id)
    ).all()
    if not legends:
        return None
    return random.Random(f"{server.id}:{day}:rate-up-legend").choice(legends)


def settle(session: Session, server: Server) -> None:
    """Decides every finale that's over and isn't yet, with the trophies of
    its player stats (`app.player_stats`). Commits. Speed mode sessions have
    no weeks."""
    if speed.is_speed(server):
        return
    today = days.current_day(server)
    decided = set(
        session.scalars(select(WeeklyHero.day).where(WeeklyHero.server_id == server.id))
    )
    day = finale_day(server, 1)
    heroes = []
    awarded = []
    while day < today:
        if day not in decided:
            # The boosts and fights nobody finished on the last day count
            # too: the fights' wins break ties.
            fights.complete_boosts(session, server, day)
            fights.complete_fights(session, server, day)
            heroes.extend(_decide(session, server, day))
            awarded.extend(player_stats.award(session, server, day))
        day += 7
    if not heroes:
        return
    # Decided together, so a week's trophies are only awarded once.
    session.add_all(heroes)
    session.add_all(awarded)
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


def latest_heroes(session: Session, server: Server) -> list[WeeklyHero]:
    """The heroes of the latest decided finale, by place; none if it had
    none."""
    finale = latest_finale(session, server)
    if finale is None:
        return []
    heroes = heroes_of(session, server, finale.day).values()
    return sorted(heroes, key=lambda h: (h.place, -h.stars, str(h.id)))
