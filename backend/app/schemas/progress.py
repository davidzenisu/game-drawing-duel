from pydantic import BaseModel

from app.rules import Rarity


class RarityProgressResponse(BaseModel):
    """A seat's progress in one rarity, see `app.progress.Progress`."""

    rarity: Rarity
    in_pool: int
    collected: int
    owned: int
    maxed: int
    unlocked_steps: int
    steps: int
    duplicates_to_max: int
    spare_duplicates: int


class ProgressResponse(BaseModel):
    """How far a player's collection has come, per rarity (basic first):
    totals only, not which characters they own."""

    player_position: int
    rarities: list[RarityProgressResponse]
