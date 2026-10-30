"""Step 5 of the daily loop, once a week: the finale.

Every challenger that won a fight decided during a week enters that week's
finale. On the week's last day (Sunday, UTC) players vote on pairs of them,
each vote adding a star. Once the week is over, the one with the most stars
joins the server's gacha pool as a hero.

A fight is decided the day it's picked (`app.fights`); the finale counts the
fights up to the day before, so Sunday's fights count for the next week.
"""

import itertools
import random
import uuid
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app import days, fights, rules
from app.models import Character, Fight, FinaleVote, Server, ServerSeat, WeeklyHero


def finale_day(server: Server, day: int) -> int:
    """The last day of `day`'s week, the day of its finale."""
    return days.week_start(server, day) + 6


def is_finale_day(server: Server, day: int) -> bool:
    return finale_day(server, day) == day


@dataclass(frozen=True)
class Contender:
    challenger: Character
    # Fights decided against it, and how many of them it won.
    fights: int
    wins: int
    # The boost stars it got the day before its fights.
    boosts: int

    @property
    def fight_stars(self) -> int:
        """Its stars before the finale: the challenger's with its boost stars."""
        return rules.challenger_stars(self.boosts)


def contenders(session: Session, server: Server, day: int) -> list[Contender]:
    """The challengers in the finale on `day`, the last day of a week: the
    ones that won a fight that week before the finale day, oldest first."""
    last_fight_day = day - 1
    week_fights = session.scalars(
        select(Fight)
        .join(ServerSeat, ServerSeat.id == Fight.owner_seat_id)
        .where(
            ServerSeat.server_id == server.id,
            Fight.day > last_fight_day - 7,
            Fight.day <= last_fight_day,
        )
        .options(selectinload(Fight.fighters), selectinload(Fight.challenger))
    ).all()
    by_challenger: dict[uuid.UUID, list[Fight]] = {}
    for fight in week_fights:
        by_challenger.setdefault(fight.challenger_id, []).append(fight)
    result = []
    for against in by_challenger.values():
        outcomes = [fights.outcome(session, f) for f in against]
        wins = sum(not o.fighters_win for o in outcomes)
        if wins:
            result.append(
                Contender(against[0].challenger, len(against), wins, outcomes[0].boosts)
            )
    return sorted(
        result,
        key=lambda c: (c.challenger.day, c.challenger.created_at, str(c.challenger.id)),
    )


def _pair_key(a: uuid.UUID, b: uuid.UUID) -> tuple[uuid.UUID, uuid.UUID]:
    return (a, b) if str(a) < str(b) else (b, a)


def pairs_for(
    server: Server, day: int, seat: ServerSeat, candidates: list[Contender]
) -> list[tuple[Character, Character]]:
    """The pairs `seat` votes on: every pair of contenders, but none with a
    challenger they drew, in an order and left/right of their own."""
    theirs = [
        c.challenger for c in candidates if c.challenger.artist_seat_id != seat.id
    ]
    rng = random.Random(f"{server.id}:{day}:{seat.id}:finale")
    pairs = [
        (a, b) if rng.random() < 0.5 else (b, a)
        for a, b in itertools.combinations(theirs, 2)
    ]
    rng.shuffle(pairs)
    return pairs


def voted_pairs(
    session: Session, seat: ServerSeat, day: int
) -> set[tuple[uuid.UUID, uuid.UUID]]:
    return {
        (v.first_id, v.second_id)
        for v in session.scalars(
            select(FinaleVote).where(
                FinaleVote.voter_seat_id == seat.id, FinaleVote.day == day
            )
        )
    }


@dataclass(frozen=True)
class Ballot:
    # The next pair to vote on, or None once you voted on every pair.
    pair: tuple[Character, Character] | None
    votes: int
    pairs: int
    contenders: int


def ballot(session: Session, server: Server, day: int, seat: ServerSeat) -> Ballot:
    """Where `seat` stands in the finale on `day`, the last day of a week."""
    candidates = contenders(session, server, day)
    pairs = pairs_for(server, day, seat, candidates)
    voted = voted_pairs(session, seat, day)
    remaining = [p for p in pairs if _pair_key(p[0].id, p[1].id) not in voted]
    return Ballot(
        pair=remaining[0] if remaining else None,
        votes=len(voted),
        pairs=len(pairs),
        contenders=len(candidates),
    )


class InvalidVote(Exception):
    pass


def vote(
    session: Session,
    server: Server,
    day: int,
    seat: ServerSeat,
    chosen_id: uuid.UUID,
    other_id: uuid.UUID,
) -> None:
    """`seat` picks `chosen_id` over `other_id`, a pair they may vote on and
    haven't yet. Commits."""
    pairs = pairs_for(server, day, seat, contenders(session, server, day))
    key = _pair_key(chosen_id, other_id)
    if key not in {_pair_key(a.id, b.id) for a, b in pairs}:
        raise InvalidVote("You can't vote on that pair")
    first_id, second_id = key
    session.add(
        FinaleVote(
            voter_seat_id=seat.id,
            day=day,
            first_id=first_id,
            second_id=second_id,
            chosen_id=chosen_id,
        )
    )
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        raise InvalidVote("You voted on that pair already") from error


def votes_for(session: Session, day: int, challenger_id: uuid.UUID) -> int:
    return session.scalar(
        select(func.count())
        .select_from(FinaleVote)
        .where(FinaleVote.day == day, FinaleVote.chosen_id == challenger_id)
    )


def _decide(session: Session, server: Server, day: int) -> WeeklyHero:
    """The finale's result: the most stars wins, then the most fights won,
    then the challenger drawn first."""
    ranked = sorted(
        (
            (c.fight_stars + votes_for(session, day, c.challenger.id), c)
            for c in contenders(session, server, day)
        ),
        key=lambda entry: (-entry[0], -entry[1].wins),
    )
    if not ranked:
        return WeeklyHero(server_id=server.id, day=day)
    stars, winner = ranked[0]
    return WeeklyHero(
        server_id=server.id,
        day=day,
        character_id=winner.challenger.id,
        stars=stars,
        votes=stars - winner.fight_stars,
    )


def settle(session: Session, server: Server) -> None:
    """Decides every finale that's over and isn't yet. Commits."""
    today = days.current_day(server)
    decided = set(
        session.scalars(select(WeeklyHero.day).where(WeeklyHero.server_id == server.id))
    )
    day = finale_day(server, 1)
    added = False
    while day < today:
        if day not in decided:
            session.add(_decide(session, server, day))
            added = True
        day += 7
    if not added:
        return
    try:
        session.commit()
    except IntegrityError:
        session.rollback()  # Someone else decided it at the same time.


def latest_hero(session: Session, server: Server) -> WeeklyHero | None:
    """The hero of the latest decided finale, if it had one."""
    hero = session.scalar(
        select(WeeklyHero)
        .where(WeeklyHero.server_id == server.id)
        .order_by(WeeklyHero.day.desc())
        .limit(1)
        .options(selectinload(WeeklyHero.character))
    )
    return hero if hero is not None and hero.character_id is not None else None
