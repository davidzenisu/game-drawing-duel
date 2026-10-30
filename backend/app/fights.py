"""Steps 3 and 4 of the daily loop: boosts for yesterday's challengers, and
fighters against the ones drawn the day before.

A challenger drawn on day D is boosted during day D + 1 and fought on day
D + 2. Every day, a player spreads `rules.BOOST_STARS` across a few of
yesterday's challengers (`boost_targets`); once the day is over, chance
spreads the ones they left. The fight is decided as soon as the fighters are
picked: they win with more stars than the challenger with its boost stars
(`rules.fighters_win`). Players who pick no fighters get random ones from
their collection once the day is over.
"""

import random
import uuid
from dataclasses import dataclass

from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app import days, pulls, rules, upgrades
from app.models import Boost, Character, Fight, Fighter, Server, ServerSeat
from app.rules import (
    BOOST_CHALLENGERS,
    BOOST_MAX_PER_CHALLENGER,
    BOOST_STARS,
    MAX_FIGHTERS,
    Rarity,
)

# The first days with challengers drawn the day before to boost, and two
# days before to fight.
FIRST_BOOST_DAY = 3
FIRST_FIGHT_DAY = 4


def _rng(*parts: object) -> random.Random:
    return random.Random(":".join(str(p) for p in parts))


def _drawn(session: Session, server: Server, day: int) -> dict[uuid.UUID, Character]:
    """The challengers drawn on `day`, by their artist's seat."""
    return {
        c.artist_seat_id: c
        for c in session.scalars(
            select(Character).where(
                Character.server_id == server.id,
                Character.day == day,
                Character.assignment_id.is_(None),
            )
        )
    }


def _fight_offset(server: Server, day: int, players: int) -> int:
    return _rng(server.id, day, "fight-offset").randint(1, players - 1)


def fight_challenger(
    session: Session, server: Server, day: int, seat: ServerSeat
) -> Character | None:
    """The challenger `seat` picks fighters against on `day`, one drawn two
    days before: the one of the player `offset` seats on in the roster,
    `offset` being picked per server and day. So when everyone drew one,
    every challenger has exactly one fight and nobody fights their own. If
    that player drew none, the next one on who did stands in."""
    if day < FIRST_FIGHT_DAY:
        return None
    seats = days.active_seats(server)
    if len(seats) < 2 or seat not in seats:
        return None
    drawn = _drawn(session, server, day - 2)
    offset = _fight_offset(server, day, len(seats))
    position = seats.index(seat)
    for step in range(len(seats)):
        other = seats[(position + offset + step) % len(seats)]
        if other.id != seat.id and other.id in drawn:
            return drawn[other.id]
    return None


def boost_targets(
    session: Session, server: Server, day: int, seat: ServerSeat
) -> list[Character]:
    """The challengers `seat` may boost on `day`, in the order they see them:
    up to `rules.BOOST_CHALLENGERS` of yesterday's, never the one they drew
    or the one they fight tomorrow. Everyone gets the challengers of the
    players the same offsets on in the roster, offsets picked per server and
    day, so when everyone drew one, every challenger is boosted by the same
    number of players and comes first for one of them. Drawers who drew
    none are made up for by the next offsets."""
    if day < FIRST_BOOST_DAY:
        return []
    seats = days.active_seats(server)
    if len(seats) < 2 or seat not in seats:
        return []
    drawn = _drawn(session, server, day - 1)
    fight_offset = _fight_offset(server, day + 1, len(seats))
    offsets = [o for o in range(1, len(seats)) if o != fight_offset]
    _rng(server.id, day, "boost-offsets").shuffle(offsets)
    fought = fight_challenger(session, server, day + 1, seat)
    position = seats.index(seat)
    targets: list[Character] = []
    for offset in offsets:
        challenger = drawn.get(seats[(position + offset) % len(seats)].id)
        if (
            challenger is None
            or challenger.artist_seat_id == seat.id
            or (fought is not None and challenger.id == fought.id)
            or challenger in targets
        ):
            continue
        targets.append(challenger)
        if len(targets) == BOOST_CHALLENGERS:
            break
    return targets


def given_boosts(session: Session, seat: ServerSeat, day: int) -> dict[uuid.UUID, int]:
    """The boost stars `seat` gave on `day`, by challenger; chance's not
    included."""
    return dict(
        session.execute(
            select(Boost.challenger_id, Boost.stars).where(
                Boost.booster_seat_id == seat.id,
                Boost.day == day,
                Boost.by_chance.is_(False),
            )
        ).all()
    )


class InvalidBoost(Exception):
    pass


def set_boosts(
    session: Session,
    server: Server,
    day: int,
    seat: ServerSeat,
    stars: dict[uuid.UUID, int],
) -> None:
    """Replaces the boost stars `seat` gives on `day` with `stars`, by
    challenger. Commits."""
    targets = {c.id for c in boost_targets(session, server, day, seat)}
    if not targets:
        raise InvalidBoost("No challengers to boost today")
    if set(stars) - targets:
        raise InvalidBoost("You can't boost that challenger today")
    if any(n < 0 or n > BOOST_MAX_PER_CHALLENGER for n in stars.values()):
        raise InvalidBoost(
            f"A challenger takes up to {BOOST_MAX_PER_CHALLENGER} of your stars"
        )
    if sum(stars.values()) > BOOST_STARS:
        raise InvalidBoost(f"You have {BOOST_STARS} stars to give")
    session.execute(
        delete(Boost).where(
            Boost.booster_seat_id == seat.id,
            Boost.day == day,
            Boost.by_chance.is_(False),
        )
    )
    session.add_all(
        Boost(booster_seat_id=seat.id, challenger_id=c, day=day, stars=n)
        for c, n in stars.items()
        if n > 0
    )
    session.commit()


def complete_boosts(session: Session, server: Server, day: int) -> None:
    """Once `day` is over, spreads the boost stars everyone left that day
    across their challengers by chance. Commits."""
    if day < FIRST_BOOST_DAY:
        return
    for seat in days.active_seats(server):
        given = given_boosts(session, seat, day)
        left = BOOST_STARS - sum(given.values())
        if left <= 0:
            continue
        targets = boost_targets(session, server, day, seat)
        spread = session.scalar(
            select(func.count())
            .select_from(Boost)
            .where(
                Boost.booster_seat_id == seat.id,
                Boost.day == day,
                Boost.by_chance.is_(True),
            )
        )
        if not targets or spread:
            continue
        rng = _rng(server.id, day, seat.id, "boosts")
        room = {c.id: BOOST_MAX_PER_CHALLENGER - given.get(c.id, 0) for c in targets}
        chance: dict[uuid.UUID, int] = {}
        for _ in range(left):
            open_ = [c for c, n in room.items() if n > 0]
            if not open_:
                break
            pick = rng.choice(open_)
            room[pick] -= 1
            chance[pick] = chance.get(pick, 0) + 1
        try:
            with session.begin_nested():
                session.add_all(
                    Boost(
                        booster_seat_id=seat.id,
                        challenger_id=c,
                        day=day,
                        stars=n,
                        by_chance=True,
                    )
                    for c, n in chance.items()
                )
        except IntegrityError:
            pass  # Someone else spread them at the same time.
    session.commit()


def boost_stars(session: Session, challenger_id: uuid.UUID) -> int:
    """The boost stars the challenger got, chance's included."""
    return session.scalar(
        select(func.coalesce(func.sum(Boost.stars), 0)).where(
            Boost.challenger_id == challenger_id
        )
    )


def fight_of(session: Session, seat: ServerSeat, day: int) -> Fight | None:
    return session.scalar(
        select(Fight)
        .where(Fight.owner_seat_id == seat.id, Fight.day == day)
        .options(selectinload(Fight.fighters))
    )


def new_fight(
    session: Session,
    seat: ServerSeat,
    day: int,
    challenger: Character,
    fighters: list[Character],
    *,
    by_chance: bool = False,
) -> Fight:
    """A fight with the fighters' upgrades as they are now, without the
    effects their owner switched off, decided right away. The boosts of the
    day before must be complete (`complete_boosts`)."""
    unlocked = upgrades.unlocked(session, seat.id)
    fighter_stars = rules.team_stars([Rarity(c.rarity) for c in fighters])
    boosted = boost_stars(session, challenger.id)
    fight = Fight(
        owner_seat_id=seat.id,
        day=day,
        challenger_id=challenger.id,
        by_chance=by_chance,
        boosts=boosted,
        fighter_stars=fighter_stars,
        challenger_stars=rules.challenger_stars(boosted),
        fighters_win=rules.fighters_win(fighter_stars, boosted),
    )
    fight.fighters = [
        Fighter(
            position=i,
            character_id=c.id,
            upgrades=",".join(unlocked[c.id].shown),
            element=unlocked[c.id].element,
        )
        for i, c in enumerate(fighters)
    ]
    session.add(fight)
    return fight


def resting(
    session: Session, server: Server, seat: ServerSeat, day: int
) -> set[uuid.UUID]:
    """The characters `seat` sent into a fight earlier in `day`'s week. Every
    character fights once a week, they're back on Monday; basic ones can
    fight every day, so nobody ever runs out (everyone draws one during the
    setup)."""
    return set(
        session.scalars(
            select(Fighter.character_id)
            .join(Fight, Fight.id == Fighter.fight_id)
            .join(Character, Character.id == Fighter.character_id)
            .where(
                Fight.owner_seat_id == seat.id,
                Character.rarity != Rarity.BASIC.value,
                Fight.day >= days.week_start(server, day),
                Fight.day < day,
            )
        ).all()
    )


def complete_fights(session: Session, server: Server, day: int) -> None:
    """Once `day` is over, picks fighters by chance for everyone who picked
    none, out of their characters that didn't fight yet that week. Commits."""
    if day < FIRST_FIGHT_DAY:
        return
    complete_boosts(session, server, day - 1)
    for seat in days.active_seats(server):
        if fight_of(session, seat, day) is not None:
            continue
        challenger = fight_challenger(session, server, day, seat)
        owned = sorted(
            set(pulls.copies(session, seat)) - resting(session, server, seat, day)
        )
        if challenger is None or not owned:
            continue
        rng = _rng(server.id, day, seat.id, "fighters")
        picks = rng.sample(owned, rng.randint(1, min(MAX_FIGHTERS, len(owned))))
        fighters = [session.get(Character, character_id) for character_id in picks]
        try:
            with session.begin_nested():
                new_fight(session, seat, day, challenger, fighters, by_chance=True)
        except IntegrityError:
            pass  # Someone else completed it at the same time.
    session.commit()


def fights_on(session: Session, server: Server, day: int) -> list[Fight]:
    return list(
        session.scalars(
            select(Fight)
            .join(ServerSeat, ServerSeat.id == Fight.owner_seat_id)
            .where(ServerSeat.server_id == server.id, Fight.day == day)
            .options(selectinload(Fight.fighters), selectinload(Fight.challenger))
            .order_by(ServerSeat.position)
        )
    )


@dataclass(frozen=True)
class Outcome:
    fighter_stars: int
    # The challenger's boost stars.
    boosts: int
    challenger_stars: int
    fighters_win: bool


def outcome(session: Session, fight: Fight) -> Outcome:
    """The stars of the fighters and of the boosted challenger: as stored
    when the fight was decided, or under the current rules for fights
    picked before results were stored."""
    if fight.fighters_win is not None:
        return Outcome(
            fight.fighter_stars, fight.boosts, fight.challenger_stars, fight.fighters_win
        )
    team = [Rarity(f.character.rarity) for f in fight.fighters]
    fighter_stars = rules.team_stars(team)
    boosted = boost_stars(session, fight.challenger_id)
    return Outcome(
        fighter_stars,
        boosted,
        rules.challenger_stars(boosted),
        rules.fighters_win(fighter_stars, boosted),
    )


def decide_fights(session: Session, server: Server) -> None:
    """Stores the result of fights picked before results were stored right
    away, so later rule changes don't rewrite them. Commits."""
    undecided = session.scalars(
        select(Fight)
        .join(ServerSeat, ServerSeat.id == Fight.owner_seat_id)
        .where(ServerSeat.server_id == server.id, Fight.fighters_win.is_(None))
        .options(selectinload(Fight.fighters).selectinload(Fighter.character))
    ).all()
    if not undecided:
        return
    for fight in undecided:
        result = outcome(session, fight)
        fight.boosts = result.boosts
        fight.fighter_stars = result.fighter_stars
        fight.challenger_stars = result.challenger_stars
        fight.fighters_win = result.fighters_win
    session.commit()


def owned_characters(
    session: Session, seat: ServerSeat, ids: list[uuid.UUID]
) -> list[Character] | None:
    """The characters with `ids` if the seat owns them all."""
    owned = pulls.copies(session, seat)
    if any(i not in owned for i in ids):
        return None
    return [session.get(Character, i) for i in ids]


@dataclass(frozen=True)
class ChallengerRecord:
    challenger: Character
    # Decided fights against it, and how many it won.
    fights: int
    wins: int


def encountered_challengers(
    session: Session, server: Server, seat: ServerSeat
) -> list[ChallengerRecord]:
    """The challengers `seat` encountered, newest first: the ones they drew,
    fought against or boosted, with their record in decided fights."""
    drawn = select(Character.id).where(
        Character.artist_seat_id == seat.id, Character.assignment_id.is_(None)
    )
    fought = select(Fight.challenger_id).where(Fight.owner_seat_id == seat.id)
    boosted_ids = select(Boost.challenger_id).where(Boost.booster_seat_id == seat.id)
    challengers = session.scalars(
        select(Character)
        .where(
            Character.server_id == server.id,
            Character.id.in_(drawn.union(fought, boosted_ids)),
        )
        .options(selectinload(Character.artist), selectinload(Character.subject))
        .order_by(Character.day.desc(), Character.created_at.desc())
    ).all()
    # Like the results, a challenger's fights count once their day is over.
    today = days.current_day(server)
    records = []
    for challenger in challengers:
        decided = session.scalars(
            select(Fight)
            .where(Fight.challenger_id == challenger.id, Fight.day < today)
            .options(selectinload(Fight.fighters), selectinload(Fight.challenger))
        ).all()
        wins = sum(not outcome(session, f).fighters_win for f in decided)
        records.append(ChallengerRecord(challenger, len(decided), wins))
    return records
