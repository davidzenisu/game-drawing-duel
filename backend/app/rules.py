"""Game rules the server enforces.

The frontend implements the same rules (`frontend/lib/game/rules`); both are
checked against `shared/rules.json`.
"""

import random
from dataclasses import dataclass
from enum import StrEnum

MIN_PLAYERS = 5
MAX_PLAYERS = 10
SERVER_CODE_LENGTH = 6


class Rarity(StrEnum):
    BASIC = "basic"
    ADVENTURER = "adventurer"
    HERO = "hero"
    LEGEND = "legend"


class SetupPrompt(StrEnum):
    """The default prompts of the initial drawing setup."""

    BASIC = "basic"
    ALTER = "alter"
    KNIGHT = "knight"
    MAGE = "mage"
    ROGUE = "rogue"
    LEGEND = "legend"

    @property
    def rarity(self) -> Rarity:
        return _PROMPT_RARITY[self]

    @property
    def based_on(self) -> "SetupPrompt | None":
        """The prompt this one builds on; it is drawn of the same subject."""
        return SetupPrompt.BASIC if self is SetupPrompt.ALTER else None


_PROMPT_RARITY = {
    SetupPrompt.BASIC: Rarity.BASIC,
    SetupPrompt.ALTER: Rarity.BASIC,
    SetupPrompt.KNIGHT: Rarity.ADVENTURER,
    SetupPrompt.MAGE: Rarity.ADVENTURER,
    SetupPrompt.ROGUE: Rarity.ADVENTURER,
    SetupPrompt.LEGEND: Rarity.LEGEND,
}

# The short setup of a test session, drawn by every player who joined.
TEST_PROMPTS = (SetupPrompt.BASIC, SetupPrompt.KNIGHT, SetupPrompt.LEGEND)


def prompts_for(player_count: int) -> tuple[SetupPrompt, ...]:
    """The prompts every player draws, so the pool holds ~30 characters."""
    if not MIN_PLAYERS <= player_count <= MAX_PLAYERS:
        raise ValueError(f"A server has {MIN_PLAYERS} to {MAX_PLAYERS} players")
    if player_count == 5:
        return tuple(SetupPrompt)
    if player_count == 6:
        return (
            SetupPrompt.BASIC,
            SetupPrompt.ALTER,
            SetupPrompt.KNIGHT,
            SetupPrompt.MAGE,
            SetupPrompt.LEGEND,
        )
    if player_count <= 8:
        return (
            SetupPrompt.BASIC,
            SetupPrompt.KNIGHT,
            SetupPrompt.MAGE,
            SetupPrompt.LEGEND,
        )
    return (SetupPrompt.BASIC, SetupPrompt.KNIGHT, SetupPrompt.LEGEND)


@dataclass(frozen=True)
class Assignment:
    prompt: SetupPrompt
    # Index of the depicted player in the list of players.
    subject: int


def assignments_for(player_count: int, artist: int) -> list[Assignment]:
    """What the player at index `artist` draws in a regular server."""
    return _assign(player_count, artist, prompts_for(player_count))


def test_assignments_for(
    player_count: int, artist: int, rng: random.Random | None = None
) -> list[Assignment]:
    """What the player at index `artist` draws in a test session: the test
    prompts of different, randomly picked other players of the whole roster,
    whether they joined or not."""
    others = [i for i in range(player_count) if i != artist]
    subjects = (rng or random.SystemRandom()).sample(others, len(TEST_PROMPTS))
    return [Assignment(p, s) for p, s in zip(TEST_PROMPTS, subjects, strict=True)]


def _assign(
    count: int, artist: int, prompts: tuple[SetupPrompt, ...]
) -> list[Assignment]:
    # Every prompt group (the alter shares its subject with the basic) shifts
    # the subject by a different offset, so nobody draws themselves and every
    # player is depicted exactly once per prompt.
    assignments = []
    group = -1
    for prompt in prompts:
        if prompt.based_on is None:
            group += 1
        offset = 1 + group % (count - 1)
        assignments.append(Assignment(prompt, (artist + offset) % count))
    return assignments


# The longest title of a drawn character.
MAX_TITLE_LENGTH = 60


class UpgradeEffect(StrEnum):
    """Special effects unlocked by spending duplicates."""

    SHADOW = "shadow"
    LIGHT = "light"
    ELEMENT = "element"
    AURA = "aura"
    HALO = "halo"


class Element(StrEnum):
    """The choice made when unlocking the element upgrade."""

    FIRE = "fire"
    ICE = "ice"
    STORM = "storm"


# Each rarity has its own (deeper) upgrade path, unlocked in order.
UPGRADE_PATHS = {
    Rarity.BASIC: (UpgradeEffect.SHADOW, UpgradeEffect.LIGHT),
    Rarity.ADVENTURER: (
        UpgradeEffect.SHADOW,
        UpgradeEffect.LIGHT,
        UpgradeEffect.ELEMENT,
    ),
    Rarity.HERO: (
        UpgradeEffect.SHADOW,
        UpgradeEffect.LIGHT,
        UpgradeEffect.ELEMENT,
        UpgradeEffect.AURA,
    ),
    Rarity.LEGEND: tuple(UpgradeEffect),
}
