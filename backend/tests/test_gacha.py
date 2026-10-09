"""Checks the gacha against `shared/rules.json`, like the frontend does."""

import random
import unittest
from collections import Counter

from app import gacha
from app.gacha import GachaState
from app.rules import Rarity
from tests.test_rules import SHARED

RULES = SHARED["gacha"]


class GachaRulesTest(unittest.TestCase):
    def test_numbers(self):
        self.assertEqual(gacha.LAUNCH_BONUS, RULES["launch_bonus"])
        self.assertEqual({r.value: w for r, w in gacha.RATES.items()}, RULES["rates"])
        self.assertEqual(gacha.BEGINNER_WINDOW, RULES["beginner_window"])
        self.assertEqual(gacha.LEGEND_PITY, RULES["legend_pity"])

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


class GachaStateTest(unittest.TestCase):
    def test_pity_follows_from_the_pulls(self):
        state = GachaState.after([Rarity.BASIC, Rarity.LEGEND, Rarity.BASIC])
        self.assertEqual(state.total_pulls, 3)
        self.assertEqual(state.pulls_since_legend, 1)
        self.assertEqual(state.pulls_until_legend, gacha.LEGEND_PITY - 1)
        self.assertTrue(state.beginner_guarantee_met)
        self.assertIsNone(state.beginner_pulls_left)
        fresh = GachaState.after([])
        self.assertEqual(fresh.beginner_pulls_left, gacha.BEGINNER_WINDOW)

    def test_the_last_beginner_pull_is_a_hero_or_legend(self):
        rng = random.Random(1)
        state = GachaState.after([Rarity.BASIC] * (gacha.BEGINNER_WINDOW - 1))
        for _ in range(200):
            rarity, guaranteed = gacha.roll_rarity(state, rng)
            self.assertIn(rarity, {Rarity.HERO, Rarity.LEGEND})
            self.assertTrue(guaranteed)

    def test_a_legend_after_the_pity_count(self):
        rng = random.Random(1)
        state = GachaState.after(
            [Rarity.HERO] + [Rarity.BASIC] * (gacha.LEGEND_PITY - 2)
        )
        self.assertEqual(gacha.roll_rarity(state, rng), (Rarity.LEGEND, True))
        pulled = gacha.pull_rarity(state, {Rarity.BASIC, Rarity.HERO}, rng)
        self.assertEqual(pulled, Rarity.HERO, "pity looks upwards first")

    def test_rates(self):
        rng = random.Random(1)
        state = GachaState.after([Rarity.HERO])
        counts = Counter(gacha.roll_rarity(state, rng)[0] for _ in range(20_000))
        for rarity, percent in gacha.RATES.items():
            self.assertAlmostEqual(counts[rarity] / 20_000 * 100, percent, delta=1.5)
