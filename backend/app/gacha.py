"""Gacha pulls with rates and pity, see `docs/concept/gacha-rates.md`.

The frontend pulls the same way in the mockup (`frontend/lib/game/rules/
gacha.dart`); both are checked against `shared/rules.json`. On the server the
pity state isn't stored: it follows from a player's pulls so far.
"""

import random
from collections.abc import Sequence
from dataclasses import dataclass

from app.rules import Rarity

# Pulls every player receives when a server launches.
LAUNCH_BONUS = 10

# Pull chances in percent.
RATES = {Rarity.BASIC: 40, Rarity.ADVENTURER: 50, Rarity.HERO: 8, Rarity.LEGEND: 2}

# Within the first pulls a 3 or 4 star character is guaranteed.
BEGINNER_WINDOW = 10

# Every this many pulls without a legend, the next one is a legend.
LEGEND_PITY = 50

_STARS = {rarity: stars for stars, rarity in enumerate(Rarity, start=1)}


@dataclass(frozen=True)
class GachaState:
    """A player's pity progress, from the rarities they pulled, oldest first."""

    total_pulls: int
    pulls_since_legend: int
    beginner_guarantee_met: bool

    @classmethod
    def after(cls, pulled: Sequence[Rarity]) -> "GachaState":
        since_legend = 0
        for rarity in pulled:
            since_legend = 0 if rarity is Rarity.LEGEND else since_legend + 1
        return cls(
            total_pulls=len(pulled),
            pulls_since_legend=since_legend,
            beginner_guarantee_met=any(
                _STARS[r] >= _STARS[Rarity.HERO] for r in pulled
            ),
        )

    @property
    def pulls_until_legend(self) -> int:
        return LEGEND_PITY - self.pulls_since_legend

    @property
    def beginner_pulls_left(self) -> int | None:
        """Pulls left within the beginner window, or None once it doesn't apply."""
        if self.beginner_guarantee_met or self.total_pulls >= BEGINNER_WINDOW:
            return None
        return BEGINNER_WINDOW - self.total_pulls


def roll_rarity(state: GachaState, rng: random.Random) -> tuple[Rarity, bool]:
    """The rarity of the next pull, and whether pity guaranteed it."""
    if state.pulls_since_legend + 1 >= LEGEND_PITY:
        return Rarity.LEGEND, True
    if not state.beginner_guarantee_met and state.total_pulls == BEGINNER_WINDOW - 1:
        hero = RATES[Rarity.HERO]
        roll = rng.randrange(hero + RATES[Rarity.LEGEND])
        return (Rarity.HERO if roll < hero else Rarity.LEGEND), True
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
    state: GachaState, available: set[Rarity], rng: random.Random
) -> Rarity:
    """The rarity tier the next pull comes from, given the pool's tiers."""
    if not available:
        raise ValueError("The pool is empty")
    wanted, guaranteed = roll_rarity(state, rng)
    return closest_available_tier(available, wanted, prefer_higher=guaranteed)
