"""Game rules the server enforces.

The frontend implements the same rules (`frontend/lib/game/rules`); both are
checked against `shared/rules.json`.
"""

import random
from dataclasses import dataclass
from datetime import date
from enum import StrEnum

MIN_PLAYERS = 5
MAX_PLAYERS = 10
SERVER_CODE_LENGTH = 6


class Rarity(StrEnum):
    BASIC = "basic"
    ADVENTURER = "adventurer"
    HERO = "hero"
    LEGEND = "legend"

    @property
    def stars(self) -> int:
        """1 for a basic up to 4 for a legend."""
        return list(Rarity).index(self) + 1


class SetupPrompt(StrEnum):
    """The default prompts of the initial drawing setup."""

    BASIC = "basic"
    ALTER = "alter"
    KNIGHT = "knight"
    MAGE = "mage"
    ROGUE = "rogue"
    # Not in any setup plan yet: kept for the speed mode.
    HERO = "hero"
    LEGEND = "legend"

    @property
    def rarity(self) -> Rarity:
        return _PROMPT_RARITY[self]

    @property
    def based_on(self) -> SetupPrompt | None:
        """The prompt this one builds on; it is drawn of the same subject."""
        return SetupPrompt.BASIC if self is SetupPrompt.ALTER else None


_PROMPT_RARITY = {
    SetupPrompt.BASIC: Rarity.BASIC,
    SetupPrompt.ALTER: Rarity.BASIC,
    SetupPrompt.KNIGHT: Rarity.ADVENTURER,
    SetupPrompt.MAGE: Rarity.ADVENTURER,
    SetupPrompt.ROGUE: Rarity.ADVENTURER,
    SetupPrompt.HERO: Rarity.HERO,
    SetupPrompt.LEGEND: Rarity.LEGEND,
}

# The short setup of a test session, drawn by every player who joined.
TEST_PROMPTS = (SetupPrompt.BASIC, SetupPrompt.KNIGHT, SetupPrompt.LEGEND)


def prompts_for(player_count: int) -> tuple[SetupPrompt, ...]:
    """The prompts every player draws, so the pool holds ~30 characters."""
    if not MIN_PLAYERS <= player_count <= MAX_PLAYERS:
        raise ValueError(f"A server has {MIN_PLAYERS} to {MAX_PLAYERS} players")
    if player_count == 5:
        return (
            SetupPrompt.BASIC,
            SetupPrompt.ALTER,
            SetupPrompt.KNIGHT,
            SetupPrompt.MAGE,
            SetupPrompt.ROGUE,
            SetupPrompt.LEGEND,
        )
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
    OUTLINE = "outline"
    LIGHT = "light"
    ELEMENT = "element"
    AURA = "aura"
    GLITTER = "glitter"
    ECHO = "echo"
    ALIVE = "alive"
    HALO = "halo"


class Element(StrEnum):
    """The choice made when unlocking the element upgrade."""

    FIRE = "fire"
    ICE = "ice"
    STORM = "storm"


# Each rarity has its own (deeper) upgrade path, unlocked in order: the
# effects every rarity gets, plus the element from 2 stars, the aura from 3
# and the halo for legends. Every path keeps the order the effects are
# declared in.
_EVERYONE = (
    UpgradeEffect.SHADOW,
    UpgradeEffect.OUTLINE,
    UpgradeEffect.LIGHT,
    UpgradeEffect.GLITTER,
    UpgradeEffect.ECHO,
    UpgradeEffect.ALIVE,
)
_FROM = {
    Rarity.BASIC: set(),
    Rarity.ADVENTURER: {UpgradeEffect.ELEMENT},
    Rarity.HERO: {UpgradeEffect.ELEMENT, UpgradeEffect.AURA},
    Rarity.LEGEND: {UpgradeEffect.ELEMENT, UpgradeEffect.AURA, UpgradeEffect.HALO},
}
UPGRADE_PATHS = {
    rarity: tuple(e for e in UpgradeEffect if e in _EVERYONE or e in extra)
    for rarity, extra in _FROM.items()
}

# How many duplicates each step of a rarity's upgrade path costs: never
# less than the step before, and the common rarities, pulled most, take
# about 30 to max out.
UPGRADE_COSTS = {
    Rarity.BASIC: (1, 2, 3, 5, 7, 10),
    Rarity.ADVENTURER: (1, 1, 2, 3, 5, 7, 10),
    Rarity.HERO: (1, 1, 1, 1, 2, 2, 3, 3),
    Rarity.LEGEND: (1, 1, 1, 1, 1, 2, 2, 2, 3),
}


class Theme(StrEnum):
    """The daily prompt themes, one per weekday from Monday to Sunday."""

    FOREST = "forest"
    BEACH = "beach"
    VOLCANO = "volcano"
    SNOW = "snow"
    JUNGLE = "jungle"
    SPACE = "space"
    CASTLE = "castle"


def theme_of_date(day: date) -> Theme:
    """The theme of a calendar day (UTC): Monday's is the forest."""
    return list(Theme)[day.weekday()]


# Up to this many fighters face a challenger.
MAX_FIGHTERS = 4

# The stars of a challenger before boosts.
CHALLENGER_STARS = 3

# Every day, a player spreads this many boost stars across this many of the
# day before's challengers, at most this many on one.
BOOST_CHALLENGERS = 3
BOOST_STARS = 3
BOOST_MAX_PER_CHALLENGER = 3


def team_stars(team: list[Rarity]) -> int:
    """The stars of a team: its rarities'. Upgrades don't count (yet)."""
    return sum(r.stars for r in team)


def challenger_stars(boost_stars: int) -> int:
    """A challenger's stars with the boost stars it got."""
    return CHALLENGER_STARS + boost_stars


def fighters_win(fighter_stars: int, boost_stars: int) -> bool:
    """The fighters win with more stars than the boosted challenger; ties go
    to the challenger."""
    return fighter_stars > challenger_stars(boost_stars)


# The time limit for drawing a challenger.
CHALLENGER_DRAW_SECONDS = 90

# A free daily hurry takes away this share of the drawing time left when it
# hits, somewhere between these fractions of the time limit. Every hurry a
# player receives counts.
HURRY_CUT_FRACTION = 0.1
HURRY_EARLIEST = 0.25
HURRY_LATEST = 0.6
