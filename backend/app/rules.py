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


# Speed mode: a one-off session of about 20 minutes. Its setup and its days
# run on these timers, back to back; challenger prompts are written on the
# first days only, so the last days finish the loop.
SPEED_SETUP_SECONDS = 300
SPEED_DAY_SECONDS = (60, 120, 180, 180, 120, 60)
SPEED_DAYS = len(SPEED_DAY_SECONDS)
SPEED_LAST_PROMPT_DAY = 3

# Per player count, the higher-rarity drawing of each artist (by roster
# index) in a speed mode setup, besides the basic one.
_SPEED_SETUP = {
    5: ("legend", "hero", "knight", "legend", "hero"),
    6: ("legend", "hero", "knight", "legend", "hero", "mage"),
    7: ("legend", "hero", "knight", "legend", "hero", "mage", "hero"),
    8: ("legend", "hero", "knight", "legend", "hero", "mage", "hero", "rogue"),
    9: (
        "legend",
        "hero",
        "knight",
        "legend",
        "hero",
        "mage",
        "legend",
        "hero",
        "rogue",
    ),
    10: (
        "legend",
        "hero",
        "knight",
        "legend",
        "hero",
        "mage",
        "legend",
        "hero",
        "rogue",
        "knight",
    ),
}


def speed_prompts_for(player_count: int) -> tuple[SetupPrompt, ...]:
    """The higher-rarity drawing of each artist in a speed mode setup."""
    if player_count not in _SPEED_SETUP:
        raise ValueError(f"A server has {MIN_PLAYERS} to {MAX_PLAYERS} players")
    return tuple(SetupPrompt(p) for p in _SPEED_SETUP[player_count])


def speed_assignments_for(player_count: int, artist: int) -> list[Assignment]:
    """What the player at index `artist` draws in a speed mode setup: the
    basic of the next player and a higher-rarity character of the one after,
    so everyone is drawn twice."""
    return [
        Assignment(SetupPrompt.BASIC, (artist + 1) % player_count),
        Assignment(
            speed_prompts_for(player_count)[artist], (artist + 2) % player_count
        ),
    ]


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


def fighters_win(
    fighter_stars: int,
    boost_stars: int,
    *,
    fighter_extra_stars: int = 0,
    challenger_extra_stars: int = 0,
) -> bool:
    """The fighters win with more stars than the boosted challenger, each
    side with its win rate extra stars; ties go to the challenger."""
    return (
        fighter_stars + fighter_extra_stars
        > challenger_stars(boost_stars) + challenger_extra_stars
    )


# A player's characters get extra stars against another player's after
# winning more than a share of last week's fights against them: the most
# extra stars of every share they beat. It takes this many fights to count.
WIN_RATE_MIN_FIGHTS = 3
WIN_RATE_EXTRA_STARS = ((0.5, 1), (0.75, 2))


def win_rate_extra_stars(wins: int, fights: int) -> int:
    """The extra stars for winning `wins` of `fights` last week."""
    if fights < WIN_RATE_MIN_FIGHTS:
        return 0
    return max(
        (stars for share, stars in WIN_RATE_EXTRA_STARS if wins > share * fights),
        default=0,
    )


# The time limit for drawing a challenger.
CHALLENGER_DRAW_SECONDS = 90

# A free daily hurry takes away these seconds of drawing time when it hits.
# Every hurry a player receives counts: they hit with between the first and
# the last seconds left, spread out.
HURRY_CUT_SECONDS = 5.0
HURRY_FIRST_LEFT_SECONDS = 55.0
HURRY_LAST_LEFT_SECONDS = 15.0

# Stars, the currency players collect (`app.stars`): writing a challenger
# title and drawing a challenger earn these; a won fight earns the
# challenger's stars.
STARS_FOR_PROMPT = 3
STARS_FOR_CHALLENGER = 3


def hurry_hits(jitters: list[float]) -> list[float]:
    """The seconds left at which each of a day's hurries hits, in the order
    they were sent, from a random share in [0, 1) each (its jitter).

    They're spread evenly: the window's time not taken by the cuts of the
    hurries before is split into one stretch per hurry, and each hits
    somewhere in its own, so together they never run past the last moment."""
    n = len(jitters)
    room = max(
        0.0,
        HURRY_FIRST_LEFT_SECONDS - HURRY_LAST_LEFT_SECONDS - (n - 1) * HURRY_CUT_SECONDS,
    )
    return [
        HURRY_FIRST_LEFT_SECONDS - i * HURRY_CUT_SECONDS - room / n * (i + jitter)
        for i, jitter in enumerate(jitters)
    ]
