"""Once a week, the finale: the week's challengers ranked, its top 3 crowned.

A challenger counts for the week of its fight, once its whole lifecycle
is through: title, drawing the day after, boosting the next day and the
fight the day after that, two days after it was drawn. A challenger titled
on a Monday is fought on Thursday and ranks that week; one titled on a
Friday is fought on Monday and ranks the next. Its stars are final by its
fight: its own 3 plus the boost stars it got. Every challenger is ranked
(`rules.finale_key`): by its boost stars, then the boost stars all of its
artist's challengers got that week, then its win rate, then the latest day
it was drawn; everyone can see the ranking.

Once the week is over, its top `rules.FINALE_MAX_HEROES` are crowned weekly
heroes and join the server's gacha pool: 1st place as a legend, 2nd as a
hero, 3rd as an adventurer (`rules.FINALE_RARITIES`).
"""

import uuid
from collections import Counter
from dataclasses import dataclass, replace

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app import days, fights, player_stats, rules, speed
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
    # The boost stars all of its artist's challengers ranked that week got,
    # its own included (as the Grand Artist player stat).
    artist_boost_stars: int = 0

    @property
    def boost_stars(self) -> int:
        return self.stars - rules.CHALLENGER_STARS

    @property
    def win_rate(self) -> float:
        """Its fights won out of its fights; 0 without any."""
        return self.wins / self.fights if self.fights else 0.0


def ranking(session: Session, server: Server, day: int) -> list[Ranked]:
    """The challengers of the week that ends on `day`, its last day, best
    first (`rules.finale_key`; then the one drawn last): the ones fought
    that week. Their boosts and fights must be
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
    by_artist: Counter[uuid.UUID] = Counter()
    for r in entries:
        by_artist[r.challenger.artist_seat_id] += r.boost_stars
    entries = [
        replace(r, artist_boost_stars=by_artist[r.challenger.artist_seat_id])
        for r in entries
    ]
    # Still tied: the one drawn last first.
    entries.sort(key=lambda r: (r.challenger.created_at, str(r.challenger.id)))
    entries.reverse()
    entries.sort(
        key=lambda r: rules.finale_key(
            r.boost_stars, r.artist_boost_stars, r.wins, r.fights, r.challenger.day
        )
    )
    return entries


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


def _decide(session: Session, server: Server, day: int) -> list[WeeklyHero]:
    """The finale's result: the top of its ranking crowned, each character
    taking the rarity of its place; one row without a character if the week
    had no challengers."""
    ranked = ranking(session, server, day)
    if not ranked:
        return [WeeklyHero(server_id=server.id, day=day)]
    heroes = []
    for place, (r, rarity) in enumerate(zip(ranked, rules.FINALE_RARITIES), 1):
        r.challenger.rarity = rarity.value
        heroes.append(
            WeeklyHero(
                server_id=server.id,
                day=day,
                character_id=r.challenger.id,
                stars=r.stars,
                place=place,
                rarity=rarity.value,
            )
        )
    return heroes


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
    return sorted(
        heroes_of(session, server, finale.day).values(), key=lambda h: h.place
    )
