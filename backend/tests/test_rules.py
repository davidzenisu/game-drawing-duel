"""Checks the rules against `shared/rules.json`, which the frontend's tests
check its own implementation against too."""

import json
import random
import unittest
from pathlib import Path

from app import rules

SHARED = json.loads(
    (Path(__file__).resolve().parents[2] / "shared" / "rules.json").read_text()
)


def _subjects(count: int, assign) -> list[list[int]]:
    return [[a.subject for a in assign(count, artist)] for artist in range(count)]


class SharedRulesTest(unittest.TestCase):
    def test_limits(self):
        self.assertEqual(rules.MIN_PLAYERS, SHARED["players"]["min"])
        self.assertEqual(rules.MAX_PLAYERS, SHARED["players"]["max"])
        self.assertEqual(rules.SERVER_CODE_LENGTH, SHARED["server_code_length"])
        self.assertEqual(rules.MAX_TITLE_LENGTH, SHARED["max_title_length"])

    def test_rarities(self):
        self.assertEqual(
            [r.value for r in rules.Rarity], [r["name"] for r in SHARED["rarities"]]
        )

    def test_setup_prompts(self):
        self.assertEqual(
            [
                {
                    "name": p.value,
                    "rarity": p.rarity.value,
                    "based_on": p.based_on and p.based_on.value,
                }
                for p in rules.SetupPrompt
            ],
            SHARED["setup_prompts"],
        )

    def test_setup_plans(self):
        self.assertEqual(
            {
                str(n): [p.value for p in rules.prompts_for(n)]
                for n in range(rules.MIN_PLAYERS, rules.MAX_PLAYERS + 1)
            },
            SHARED["setup_plans"],
        )
        self.assertEqual([p.value for p in rules.TEST_PROMPTS], SHARED["test_setup"])

    def test_unsupported_player_counts(self):
        for count in (rules.MIN_PLAYERS - 1, rules.MAX_PLAYERS + 1):
            with self.assertRaises(ValueError):
                rules.prompts_for(count)

    def test_assignments(self):
        for count, expected in SHARED["assignments"].items():
            with self.subTest(players=count):
                self.assertEqual(_subjects(int(count), rules.assignments_for), expected)

    def test_test_session_subjects_are_random_other_players(self):
        rng = random.Random(1)
        for count in range(rules.MIN_PLAYERS, rules.MAX_PLAYERS + 1):
            seen = set()
            for artist in range(count):
                for _ in range(20):
                    planned = rules.test_assignments_for(count, artist, rng)
                    self.assertEqual(
                        [a.prompt.value for a in planned], SHARED["test_setup"]
                    )
                    subjects = [a.subject for a in planned]
                    self.assertEqual(len(set(subjects)), len(subjects))
                    self.assertNotIn(artist, subjects)
                    seen.update(subjects)
            self.assertEqual(seen, set(range(count)), "everyone can be drawn")

    def test_upgrades(self):
        self.assertEqual(
            {r.value: [e.value for e in p] for r, p in rules.UPGRADE_PATHS.items()},
            SHARED["upgrades"]["paths"],
        )
        self.assertEqual(
            [e.value for e in rules.Element], SHARED["upgrades"]["elements"]
        )

    def test_themes(self):
        self.assertEqual([t.value for t in rules.Theme], SHARED["themes"])
        self.assertEqual(rules.theme_of_day(1), rules.Theme.FOREST)
        self.assertEqual(rules.theme_of_day(len(rules.Theme) + 2), rules.Theme.BEACH)

    def test_fights(self):
        fights = SHARED["fights"]
        self.assertEqual(rules.MAX_FIGHTERS, fights["max_fighters"])
        self.assertEqual(
            {r.value: p for r, p in rules.RARITY_POWER.items()}, fights["rarity_power"]
        )
        self.assertEqual(rules.UPGRADE_POWER, fights["upgrade_power"])
        self.assertEqual(rules.CHALLENGER_POWER, fights["challenger_power"])
        odds = rules.fighter_odds([(rules.Rarity.LEGEND, 2), (rules.Rarity.BASIC, 0)])
        self.assertAlmostEqual(odds, 4.8 / 9.8)
