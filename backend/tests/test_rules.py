"""Checks the rules against `shared/rules.json`, which the frontend's tests
check its own implementation against too."""

import json
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
        for count, expected in SHARED["test_assignments"].items():
            with self.subTest(active=count):
                self.assertEqual(
                    _subjects(int(count), rules.test_assignments_for), expected
                )
