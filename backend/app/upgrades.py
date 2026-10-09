"""Unlocking upgrades with duplicates."""

import uuid
from collections import defaultdict
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Character, ServerSeat, Upgrade
from app.pulls import copies
from app.rules import UPGRADE_PATHS, Element, Rarity, UpgradeEffect


@dataclass
class Unlocked:
    """A character's unlocked upgrades, in path order, and its element."""

    effects: list[UpgradeEffect] = field(default_factory=list)
    element: Element | None = None


def unlocked(session: Session, seat_id: uuid.UUID) -> dict[uuid.UUID, Unlocked]:
    by_character: dict[uuid.UUID, Unlocked] = defaultdict(Unlocked)
    for upgrade in session.scalars(select(Upgrade).where(Upgrade.seat_id == seat_id)):
        entry = by_character[upgrade.character_id]
        entry.effects.append(UpgradeEffect(upgrade.effect))
        if upgrade.element:
            entry.element = Element(upgrade.element)
    # Every path lists the effects in the order they're declared in.
    order = list(UpgradeEffect)
    for entry in by_character.values():
        entry.effects.sort(key=order.index)
    return by_character


class UpgradeRejected(Exception):
    """Why the next upgrade can't be unlocked."""


class ElementRequired(UpgradeRejected):
    pass


def unlock_next(
    session: Session, seat: ServerSeat, character: Character, element: Element | None
) -> None:
    """Unlocks the character's next upgrade with one duplicate.

    Locks the seat meanwhile, like pulls do; the caller commits.
    """
    session.scalar(
        select(ServerSeat.id).where(ServerSeat.id == seat.id).with_for_update()
    )
    owned = copies(session, seat).get(character.id, 0)
    if not owned:
        raise UpgradeRejected("You don't own this character")
    done = unlocked(session, seat.id)[character.id].effects
    path = UPGRADE_PATHS[Rarity(character.rarity)]
    if len(done) >= len(path):
        raise UpgradeRejected("Every upgrade is unlocked already")
    if owned - 1 - len(done) < 1:
        raise UpgradeRejected("You need a duplicate to unlock this")
    effect = path[len(done)]
    if effect is UpgradeEffect.ELEMENT and element is None:
        raise ElementRequired("Choose an element for this upgrade")
    session.add(
        Upgrade(
            seat_id=seat.id,
            character_id=character.id,
            effect=effect.value,
            element=element.value if effect is UpgradeEffect.ELEMENT else None,
        )
    )
