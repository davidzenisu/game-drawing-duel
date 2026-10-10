"""Steps 3 and 4 of the daily loop: fighters against yesterday's challengers,
and votes on who wins.

A fight set up on day F is voted on during day F + 1 and decided from day
F + 2 on. Whatever a player leaves out is decided by chance: fighters picked
at random from their collection, votes weighted by `rules.fighter_odds`.
"""

import random
import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app import days, pulls, upgrades
from app.models import Character, Fight, Fighter, Server, ServerSeat, Vote
from app.rules import MAX_FIGHTERS, Rarity, fighter_odds

# The first day with challengers drawn the day before.
FIRST_FIGHT_DAY = 3


def _rng(*parts: object) -> random.Random:
    return random.Random(":".join(str(p) for p in parts))


def fight_challenger(
    session: Session, server: Server, day: int, seat: ServerSeat
) -> Character | None:
    """The challenger `seat` picks fighters against on `day`: one of the day
    before's, not their own."""
    if day < FIRST_FIGHT_DAY:
        return None
    candidates = session.scalars(
        select(Character)
        .where(
            Character.server_id == server.id,
            Character.day == day - 1,
            Character.artist_seat_id != seat.id,
        )
        .order_by(Character.id)
    ).all()
    return (
        _rng(server.id, day, seat.id, "fight").choice(candidates)
        if candidates
        else None
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


def complete_fights(session: Session, server: Server, day: int) -> None:
    """Picks fighters by chance for everyone who picked none on `day`, so the
    others can vote on their fight. Commits."""
    if day < FIRST_FIGHT_DAY:
        return
    for seat in days.active_seats(server):
        if fight_of(session, seat, day) is not None:
            continue
        challenger = fight_challenger(session, server, day, seat)
        owned = sorted(pulls.copies(session, seat))
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


def can_vote(fight: Fight, seat: ServerSeat) -> bool:
    """Everyone votes but the owner and the challenger's artist."""
    return seat.id not in {fight.owner_seat_id, fight.challenger.artist_seat_id}


@dataclass(frozen=True)
class Outcome:
    fighter_votes: int
    challenger_votes: int

    @property
    def fighters_win(self) -> bool:
        """Ties go to the challenger."""
        return self.fighter_votes > self.challenger_votes


def outcome(session: Session, server: Server, fight: Fight) -> Outcome:
    """The votes cast, and a vote by chance for everyone who didn't."""
    cast = {
        vote.voter_seat_id: vote.fighters_win
        for vote in session.scalars(select(Vote).where(Vote.fight_id == fight.id))
    }
    unlocked = [
        (Rarity(f.character.rarity), len(f.upgrades.split(",")) if f.upgrades else 0)
        for f in fight.fighters
    ]
    odds = fighter_odds(unlocked)
    votes = [
        cast[seat.id]
        if seat.id in cast
        else _rng(fight.id, seat.id, "vote").random() < odds
        for seat in days.active_seats(server)
        if can_vote(fight, seat)
    ]
    return Outcome(sum(votes), len(votes) - sum(votes))


def your_vote(session: Session, fight: Fight, seat: ServerSeat) -> bool | None:
    return session.scalar(
        select(Vote.fighters_win).where(
            Vote.fight_id == fight.id, Vote.voter_seat_id == seat.id
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
