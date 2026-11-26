"""How far a seat's collection has come, per rarity: the same numbers the
app's Progress screen shows (`frontend/lib/game/rules/progress.dart`), so
other players' progress can be shown without sending their collection."""

from dataclasses import dataclass, fields
from typing import Self

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import pulls, upgrades
from app.models import Character, ServerSeat
from app.rules import UPGRADE_COSTS, UPGRADE_PATHS, Rarity


@dataclass
class Progress:
    # Characters of the pool, and how many of them the seat owns.
    in_pool: int = 0
    collected: int = 0
    # Characters the seat owns, from outside the pool too (challengers
    # pulled before they left it).
    owned: int = 0
    # Owned characters with every upgrade unlocked.
    maxed: int = 0
    # Upgrades unlocked on owned characters, out of all their steps.
    unlocked_steps: int = 0
    steps: int = 0
    # Duplicates still needed to max out every owned character.
    duplicates_to_max: int = 0
    # Duplicates not spent on upgrades, maxed out characters' included.
    spare_duplicates: int = 0

    def __iadd__(self, other: Progress) -> Self:
        for f in fields(self):
            setattr(self, f.name, getattr(self, f.name) + getattr(other, f.name))
        return self


def _of_owned(rarity: Rarity, copies: int, unlocked: set, *, in_pool: bool) -> Progress:
    path = UPGRADE_PATHS[rarity]
    costs = UPGRADE_COSTS[rarity]
    locked = [c for e, c in zip(path, costs) if e not in unlocked]
    spent = sum(c for e, c in zip(path, costs) if e in unlocked)
    points = copies - 1 - spent
    to_max = sum(locked) - max(points, 0)
    return Progress(
        in_pool=int(in_pool),
        collected=int(in_pool),
        owned=1,
        maxed=int(not locked),
        unlocked_steps=len(path) - len(locked),
        steps=len(path),
        duplicates_to_max=max(to_max, 0),
        spare_duplicates=max(points, 0),
    )


def by_rarity(session: Session, seat: ServerSeat) -> dict[Rarity, Progress]:
    """The seat's progress per rarity; characters it owns from outside the
    pool count as owned, but not towards the pool."""
    owned = pulls.copies(session, seat)
    done = upgrades.unlocked(session, seat.id)
    pool = dict(
        session.execute(
            select(Character.id, Character.rarity).where(
                Character.server_id == seat.server_id, pulls.in_pool()
            )
        ).all()
    )
    outside = set(owned) - set(pool)
    rarities = pool | dict(
        session.execute(
            select(Character.id, Character.rarity).where(Character.id.in_(outside))
        ).all()
        if outside
        else {}
    )
    result = {rarity: Progress() for rarity in Rarity}
    for character_id, rarity in pool.items():
        if character_id not in owned:
            result[Rarity(rarity)] += Progress(in_pool=1)
    for character_id, copies in owned.items():
        rarity = Rarity(rarities[character_id])
        result[rarity] += _of_owned(
            rarity,
            copies,
            set(done[character_id].effects) if character_id in done else set(),
            in_pool=character_id in pool,
        )
    return result
