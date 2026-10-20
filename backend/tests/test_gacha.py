"""Checks the gacha against `shared/rules.json`, like the frontend does."""

import random
import unittest
from collections import Counter

from app import gacha
from app.gacha import Banner, GachaState
from app.rules import Rarity
from tests.test_rules import SHARED

RULES = SHARED["gacha"]


class GachaRulesTest(unittest.TestCase):
    def test_numbers(self):
        self.assertEqual(gacha.LAUNCH_BONUS, RULES["launch_bonus"])
        self.assertEqual({r.value: w for r, w in gacha.RATES.items()}, RULES["rates"])
        self.assertEqual(gacha.BEGINNER_WINDOW, RULES["beginner_window"])
        self.assertEqual(gacha.LEGEND_PITY, RULES["legend_pity"])
        self.assertEqual(gacha.RATE_UP, RULES["rate_up"])

    def test_tier_fallback(self):
        for available, wanted, guaranteed, expected in RULES["tier_fallback"]:
            with self.subTest(
                available=available, wanted=wanted, guaranteed=guaranteed
            ):
                tier = gacha.closest_available_tier(
                    {Rarity(r) for r in available},
                    Rarity(wanted),
                    prefer_higher=guaranteed,
                )
                self.assertEqual(tier.value, expected)


STANDARD, WEEKLY = Banner.STANDARD, Banner.WEEKLY


def on(banner: Banner, *rarities: Rarity) -> list[tuple[Banner, Rarity]]:
    return [(banner, rarity) for rarity in rarities]


class GachaStateTest(unittest.TestCase):
    def test_pity_follows_from_the_pulls(self):
        state = GachaState.after(on(STANDARD, Rarity.BASIC, Rarity.LEGEND, Rarity.BASIC))
        self.assertEqual(state.total_pulls, 3)
        self.assertEqual(state.pulls_since_legend, 1)
        self.assertEqual(state.pulls_until_legend, gacha.LEGEND_PITY - 1)
        self.assertTrue(state.beginner_guarantee_met)
        self.assertIsNone(state.beginner_pulls_left)
        fresh = GachaState.after([])
        self.assertEqual(fresh.beginner_pulls_left, gacha.BEGINNER_WINDOW)

    def test_the_legend_pity_counts_every_banner(self):
        state = GachaState.after(
            on(STANDARD, Rarity.BASIC) + on(WEEKLY, Rarity.LEGEND, Rarity.HERO)
        )
        self.assertEqual(state.pulls_since_legend, 1)
        # A legend on the weekly banner isn't the standard banner's guarantee.
        self.assertFalse(state.beginner_guarantee_met)
        self.assertEqual(state.beginner_pulls_left, gacha.BEGINNER_WINDOW - 1)

    def test_the_last_beginner_pull_on_the_standard_banner_is_a_legend(self):
        rng = random.Random(1)
        state = GachaState.after(
            on(WEEKLY, Rarity.HERO)
            + on(STANDARD, *[Rarity.BASIC] * (gacha.BEGINNER_WINDOW - 1))
        )
        self.assertEqual(state.beginner_pulls_left, 1)
        for _ in range(200):
            self.assertEqual(
                gacha.roll_rarity(state, STANDARD, rng), (Rarity.LEGEND, True)
            )
        # Not on the weekly banner, and not once the window is over.
        self.assertFalse(
            all(gacha.roll_rarity(state, WEEKLY, rng)[1] for _ in range(200))
        )
        over = GachaState.after(on(STANDARD, *[Rarity.BASIC] * gacha.BEGINNER_WINDOW))
        self.assertIsNone(over.beginner_pulls_left)

    def test_a_legend_after_the_pity_count(self):
        rng = random.Random(1)
        state = GachaState.after(
            on(WEEKLY, Rarity.HERO, *[Rarity.BASIC] * (gacha.LEGEND_PITY - 2))
        )
        self.assertEqual(gacha.roll_rarity(state, WEEKLY, rng), (Rarity.LEGEND, True))
        pulled = gacha.pull_rarity(state, WEEKLY, {Rarity.BASIC, Rarity.HERO}, rng)
        self.assertEqual(pulled, Rarity.HERO, "pity looks upwards first")

    def test_rates(self):
        rng = random.Random(1)
        state = GachaState.after(on(STANDARD, Rarity.HERO))
        counts = Counter(
            gacha.roll_rarity(state, STANDARD, rng)[0] for _ in range(20_000)
        )
        for rarity, percent in gacha.RATES.items():
            self.assertAlmostEqual(counts[rarity] / 20_000 * 100, percent, delta=1.5)


class RateUpTest(unittest.TestCase):
    """Rate-up characters share half of their rarity's pulls."""

    def picks(self, candidates: list[str], featured: set[str]) -> Counter:
        rng = random.Random(7)
        return Counter(
            gacha.pick_character(candidates, featured.__contains__, rng)
            for _ in range(20000)
        )

    def test_a_featured_character_gets_half_of_its_rarity(self) -> None:
        picks = self.picks(["hero", "a", "b", "c"], {"hero"})
        self.assertAlmostEqual(picks["hero"] / 20000, gacha.RATE_UP / 100, delta=0.02)
        for other in "abc":
            self.assertAlmostEqual(picks[other] / 20000, 0.5 / 3, delta=0.02)

    def test_alone_in_its_rarity_it_is_every_pull(self) -> None:
        self.assertEqual(self.picks(["hero"], {"hero"}), Counter({"hero": 20000}))

    def test_without_featured_characters_all_are_equally_likely(self) -> None:
        picks = self.picks(["a", "b"], set())
        self.assertAlmostEqual(picks["a"] / 20000, 0.5, delta=0.02)
        # A rarity of nothing but featured characters, too.
        picks = self.picks(["a", "b"], {"a", "b"})
        self.assertAlmostEqual(picks["a"] / 20000, 0.5, delta=0.02)
