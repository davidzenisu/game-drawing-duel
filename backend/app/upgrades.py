"""Unlocking upgrades with duplicates."""

import uuid
from collections import defaultdict
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Character, ServerSeat, Upgrade
from app.pulls import copies
from app.rules import UPGRADE_COSTS, UPGRADE_PATHS, Element, Rarity, UpgradeEffect


@dataclass
class Unlocked:
    """A character's unlocked upgrades, in path order, its element and the
    effects the player switched off."""

    effects: list[UpgradeEffect] = field(default_factory=list)
    element: Element | None = None
    hidden: set[UpgradeEffect] = field(default_factory=set)

    @property
    def shown(self) -> list[UpgradeEffect]:
        """The effects to show: the unlocked ones not switched off."""
        return [e for e in self.effects if e not in self.hidden]


def unlocked(session: Session, seat_id: uuid.UUID) -> dict[uuid.UUID, Unlocked]:
    by_character: dict[uuid.UUID, Unlocked] = defaultdict(Unlocked)
    for upgrade in session.scalars(select(Upgrade).where(Upgrade.seat_id == seat_id)):
        entry = by_character[upgrade.character_id]
        entry.effects.append(UpgradeEffect(upgrade.effect))
        if upgrade.hidden:
            entry.hidden.add(UpgradeEffect(upgrade.effect))
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
    """Unlocks the character's next upgrade, spending as many duplicates as
    it costs (`UPGRADE_COSTS`).

    Locks the seat meanwhile, like pulls do; the caller commits.
    """
    session.scalar(
        select(ServerSeat.id).where(ServerSeat.id == seat.id).with_for_update()
    )
    owned = copies(session, seat).get(character.id, 0)
    if not owned:
        raise UpgradeRejected("You don't own this character")
    done = set(unlocked(session, seat.id)[character.id].effects)
    path = UPGRADE_PATHS[Rarity(character.rarity)]
    costs = UPGRADE_COSTS[Rarity(character.rarity)]
    # The first step not unlocked yet: upgrades unlocked before a path grew
    # keep their place, and cost what their step costs now.
    step = next((i for i, e in enumerate(path) if e not in done), None)
    if step is None:
        raise UpgradeRejected("Every upgrade is unlocked already")
    spare = owned - 1 - sum(c for e, c in zip(path, costs) if e in done)
    if spare < costs[step]:
        missing = costs[step] - max(spare, 0)
        raise UpgradeRejected(
            f"You need {missing} more duplicate{'s' if missing > 1 else ''} to unlock this"
        )
    effect = path[step]
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


def hide(
    session: Session, seat: ServerSeat, character: Character, hidden: set[UpgradeEffect]
) -> None:
    """Switches the character's unlocked effects in `hidden` off and the
    others on; the caller commits."""
    rows = session.scalars(
        select(Upgrade).where(
            Upgrade.seat_id == seat.id, Upgrade.character_id == character.id
        )
    ).all()
    locked = hidden - {UpgradeEffect(row.effect) for row in rows}
    if locked:
        raise UpgradeRejected(
            f"Unlock {', '.join(sorted(e.value for e in locked))} first"
        )
    for row in rows:
        row.hidden = UpgradeEffect(row.effect) in hidden
