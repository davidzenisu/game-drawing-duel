"""Awarding and spending gacha pulls."""

import random
import uuid
from collections import defaultdict
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.gacha import LAUNCH_BONUS, GachaState, pull_rarity
from app.models import Character, Pull, PullGrant, ServerSeat
from app.rules import Rarity


def grant_launch_bonus(session: Session, seats: list[ServerSeat]) -> None:
    """The pulls every player receives when the game launches."""
    session.add_all(
        PullGrant(seat_id=seat.id, reason=f"launch-bonus:{n}")
        for seat in seats
        for n in range(1, LAUNCH_BONUS + 1)
    )


def _unspent_grants(seat_id: uuid.UUID):
    return (
        select(PullGrant)
        .outerjoin(Pull, Pull.grant_id == PullGrant.id)
        .where(PullGrant.seat_id == seat_id, Pull.id.is_(None))
    )


def tickets(session: Session, seat_id: uuid.UUID) -> int:
    """How many pulls the seat has left."""
    return session.scalar(
        select(func.count()).select_from(_unspent_grants(seat_id).subquery())
    )


def gacha_state(session: Session, seat_id: uuid.UUID) -> GachaState:
    return GachaState.after(_pulled(session, seat_id))


def _pulled(session: Session, seat_id: uuid.UUID) -> list[Rarity]:
    """The rarities the seat pulled, in order."""
    rarities = session.scalars(
        select(Pull.rarity).where(Pull.seat_id == seat_id).order_by(Pull.number)
    )
    return [Rarity(r) for r in rarities]


def copies(session: Session, seat: ServerSeat) -> dict[uuid.UUID, int]:
    """How many copies of each character the seat owns: the ones they drew
    during the setup, plus every pull."""
    owned: dict[uuid.UUID, int] = defaultdict(int)
    for character_id in session.scalars(
        select(Character.id).where(
            Character.artist_seat_id == seat.id, Character.assignment_id.is_not(None)
        )
    ):
        owned[character_id] += 1
    for character_id in session.scalars(
        select(Pull.character_id).where(Pull.seat_id == seat.id)
    ):
        owned[character_id] += 1
    return owned


class NotEnoughPulls(Exception):
    pass


@dataclass(frozen=True)
class Outcome:
    character: Character
    is_new: bool
    copies: int


def pull(
    session: Session,
    seat: ServerSeat,
    count: int,
    rng: random.Random | None = None,
) -> list[Outcome]:
    """Spends `count` of the seat's grants on characters of its server's pool.

    Locks the seat, so the same player pulling twice at once waits instead of
    spending the same grants; the caller commits.
    """
    rng = rng or random.SystemRandom()
    session.scalar(
        select(ServerSeat.id).where(ServerSeat.id == seat.id).with_for_update()
    )
    grants = session.scalars(
        _unspent_grants(seat.id).order_by(PullGrant.granted_at).limit(count)
    ).all()
    if len(grants) < count:
        raise NotEnoughPulls
    by_rarity: dict[Rarity, list[Character]] = defaultdict(list)
    for character in session.scalars(
        select(Character)
        .where(Character.server_id == seat.server_id)
        .order_by(Character.id)
    ):
        by_rarity[Rarity(character.rarity)].append(character)
    pulled = _pulled(session, seat.id)
    owned = copies(session, seat)
    outcomes = []
    for grant in grants:
        rarity = pull_rarity(GachaState.after(pulled), set(by_rarity), rng)
        character = rng.choice(by_rarity[rarity])
        pulled.append(rarity)
        owned[character.id] += 1
        session.add(
            Pull(
                seat_id=seat.id,
                grant_id=grant.id,
                number=len(pulled),
                character_id=character.id,
                rarity=rarity.value,
            )
        )
        outcomes.append(
            Outcome(
                character, is_new=owned[character.id] == 1, copies=owned[character.id]
            )
        )
    return outcomes
