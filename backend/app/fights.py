"""Steps 3 and 4 of the daily loop: fighters against yesterday's challengers,
and boosts for them.

Fighters are picked against a challenger on day F, the other players may
boost it during day F + 1, and from day F + 2 on the stars decide: the
fighters win with more stars than the challenger (`rules.fighters_win`).
Players who pick no fighters get random ones from their collection.
"""

import random
import uuid
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app import days, pulls, rules, upgrades
from app.models import Boost, Character, Fight, Fighter, Server, ServerSeat
from app.rules import MAX_FIGHTERS, Rarity

# The first day with challengers drawn the day before.
FIRST_FIGHT_DAY = 3


def _rng(*parts: object) -> random.Random:
    return random.Random(":".join(str(p) for p in parts))


def fight_challenger(
    session: Session, server: Server, day: int, seat: ServerSeat
) -> Character | None:
    """The challenger `seat` picks fighters against on `day`, one drawn the day
    before: the one of the player `offset` seats on in the roster, `offset`
    being picked per server and day. So when everyone drew one, every
    challenger has exactly one fight and nobody fights their own, and each
    player may boost all others but the one they drew and the one they
    fought. If that player drew none, the next one on who did stands in."""
    if day < FIRST_FIGHT_DAY:
        return None
    seats = days.active_seats(server)
    if len(seats) < 2 or seat not in seats:
        return None
    drawn = {
        c.artist_seat_id: c
        for c in session.scalars(
            select(Character).where(
                Character.server_id == server.id,
                Character.day == day - 1,
                Character.assignment_id.is_(None),
            )
        )
    }
    offset = _rng(server.id, day, "fight-offset").randint(1, len(seats) - 1)
    position = seats.index(seat)
    for step in range(len(seats)):
        other = seats[(position + offset + step) % len(seats)]
        if other.id != seat.id and other.id in drawn:
            return drawn[other.id]
    return None


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
    """A fight with the fighters' upgrades as they are now."""
    unlocked = upgrades.unlocked(session, seat.id)
    fight = Fight(
        owner_seat_id=seat.id, day=day, challenger_id=challenger.id, by_chance=by_chance
    )
    fight.fighters = [
        Fighter(
            position=i,
            character_id=c.id,
            upgrades=",".join(unlocked[c.id].effects),
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
    """Picks fighters by chance for everyone who picked none on `day`, so the
    others can boost their challenger, out of their characters that didn't
    fight yet that week. Commits."""
    if day < FIRST_FIGHT_DAY:
        return
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


def boosts(session: Session, challenger_id: uuid.UUID) -> int:
    """How many players boosted the challenger."""
    return session.scalar(
        select(func.count())
        .select_from(Boost)
        .where(Boost.challenger_id == challenger_id)
    )


@dataclass(frozen=True)
class Outcome:
    fighter_stars: int
    boosts: int

    @property
    def challenger_stars(self) -> int:
        return rules.challenger_stars(self.boosts)

    @property
    def fighters_win(self) -> bool:
        return rules.fighters_win(self.fighter_stars, self.boosts)


def outcome(session: Session, fight: Fight) -> Outcome:
    """The stars of the fighters and of the boosted challenger."""
    team = [Rarity(f.character.rarity) for f in fight.fighters]
    return Outcome(rules.team_stars(team), boosts(session, fight.challenger_id))


def boost_targets(
    session: Session, server: Server, day: int, seat: ServerSeat
) -> dict[uuid.UUID, list[Fight]]:
    """The challengers `seat` may boost on `day`, with the fights against
    them: the day before's, but not the one they drew or the one they
    fought."""
    fought = fight_of(session, seat, day - 1)
    targets: dict[uuid.UUID, list[Fight]] = {}
    for fight in fights_on(session, server, day - 1):
        challenger = fight.challenger
        if challenger.artist_seat_id == seat.id or (
            fought is not None and challenger.id == fought.challenger_id
        ):
            continue
        targets.setdefault(challenger.id, []).append(fight)
    return targets


def boosted(session: Session, seat: ServerSeat, day: int) -> uuid.UUID | None:
    """The challenger `seat` boosted on `day`, if any."""
    return session.scalar(
        select(Boost.challenger_id).where(
            Boost.booster_seat_id == seat.id, Boost.day == day
        )
    )


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
    # A fight is decided once the day after it, its boosting day, is over.
    decided_before = days.current_day(server) - 1
    records = []
    for challenger in challengers:
        decided = session.scalars(
            select(Fight)
            .where(Fight.challenger_id == challenger.id, Fight.day < decided_before)
            .options(selectinload(Fight.fighters), selectinload(Fight.challenger))
        ).all()
        wins = sum(not outcome(session, f).fighters_win for f in decided)
        records.append(ChallengerRecord(challenger, len(decided), wins))
    return records
