"""Gacha pulls with rates and pity, see `docs/concept/gacha-rates.md`.

The frontend pulls the same way in the mockup (`frontend/lib/game/rules/
gacha.dart`); both are checked against `shared/rules.json`. On the server the
pity state isn't stored: it follows from a player's pulls so far.
"""

import random
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from enum import StrEnum

from app.rules import Rarity

# Pulls every player receives when a server launches.
LAUNCH_BONUS = 10

# Pull chances in percent.
RATES = {Rarity.BASIC: 40, Rarity.ADVENTURER: 50, Rarity.HERO: 8, Rarity.LEGEND: 2}

# Within the first pulls on the standard banner, a legend is guaranteed once.
BEGINNER_WINDOW = 10

# Every this many pulls without a legend, the next one is a legend.
LEGEND_PITY = 50

# A pull landing on a rarity with rate-up characters picks one of them this
# often (percent), as long as the rarity has others too.
RATE_UP = 50

_STARS = {rarity: stars for stars, rarity in enumerate(Rarity, start=1)}


class Banner(StrEnum):
    """What a pull draws from. The standard banner is always there: the
    setup drawings, with a legend guaranteed within the first pulls on it.
    The weekly banner is the whole pool, weekly heroes included, with this
    week's rate-up (`app.pulls.rate_up`); it opens with the first finale."""

    STANDARD = "standard"
    WEEKLY = "weekly"


@dataclass(frozen=True)
class GachaState:
    """A player's pity progress, from the banners and rarities they pulled,
    oldest first. The legend pity counts the pulls on every banner, the
    beginner guarantee only the ones on the standard banner."""

    total_pulls: int
    pulls_since_legend: int
    standard_pulls: int
    beginner_guarantee_met: bool

    @classmethod
    def after(cls, pulled: Sequence[tuple[Banner, Rarity]]) -> GachaState:
        since_legend = 0
        for _, rarity in pulled:
            since_legend = 0 if rarity is Rarity.LEGEND else since_legend + 1
        standard = [rarity for banner, rarity in pulled if banner is Banner.STANDARD]
        return cls(
            total_pulls=len(pulled),
            pulls_since_legend=since_legend,
            standard_pulls=len(standard),
            beginner_guarantee_met=Rarity.LEGEND in standard,
        )

    @property
    def pulls_until_legend(self) -> int:
        return LEGEND_PITY - self.pulls_since_legend

    @property
    def beginner_pulls_left(self) -> int | None:
        """Standard pulls left within the beginner window, or None once it
        doesn't apply."""
        if self.beginner_guarantee_met or self.standard_pulls >= BEGINNER_WINDOW:
            return None
        return BEGINNER_WINDOW - self.standard_pulls


def roll_rarity(
    state: GachaState, banner: Banner, rng: random.Random
) -> tuple[Rarity, bool]:
    """The rarity of the next pull on `banner`, and whether pity guaranteed it."""
    if state.pulls_since_legend + 1 >= LEGEND_PITY:
        return Rarity.LEGEND, True
    if banner is Banner.STANDARD and state.beginner_pulls_left == 1:
        return Rarity.LEGEND, True
    rarities = list(RATES)
    return rng.choices(rarities, weights=[RATES[r] for r in rarities])[0], False


def closest_available_tier(
    available: set[Rarity], wanted: Rarity, *, prefer_higher: bool
) -> Rarity:
    """The tier to pull from when `wanted` has no characters: the nearest
    available one. Guaranteed pulls look upwards first so pity never hands out
    something worse."""
    if wanted in available:
        return wanted
    higher = [r for r in Rarity if _STARS[r] > _STARS[wanted] and r in available]
    lower = [
        r for r in reversed(Rarity) if _STARS[r] < _STARS[wanted] and r in available
    ]
    return (higher + lower if prefer_higher else lower + higher)[0]


def pull_rarity(
    state: GachaState, banner: Banner, available: set[Rarity], rng: random.Random
) -> Rarity:
    """The rarity tier the next pull on `banner` comes from, given its tiers."""
    if not available:
        raise ValueError("The pool is empty")
    wanted, guaranteed = roll_rarity(state, banner, rng)
    return closest_available_tier(available, wanted, prefer_higher=guaranteed)


def pick_character[T](candidates: Sequence[T], rate_up: Callable[[T], bool], rng: random.Random) -> T:
    """One of a rarity's characters, all equally likely, except that the
    rate-up ones share `RATE_UP` percent of the rarity when it has others."""
    featured = [c for c in candidates if rate_up(c)]
    others = [c for c in candidates if not rate_up(c)]
    if featured and others:
        return rng.choice(featured if rng.randrange(100) < RATE_UP else others)
    return rng.choice(candidates)
