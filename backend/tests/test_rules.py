"""Checks the rules against `shared/rules.json`, which the frontend's tests
check its own implementation against too."""

import json
import random
import unittest
from datetime import date
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
        self.assertEqual(
            [r.stars for r in rules.Rarity], [r["stars"] for r in SHARED["rarities"]]
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
        self.assertEqual(
            {r.value: list(c) for r, c in rules.UPGRADE_COSTS.items()},
            SHARED["upgrades"]["costs"],
        )
        for rarity, path in rules.UPGRADE_PATHS.items():
            costs = rules.UPGRADE_COSTS[rarity]
            self.assertEqual(len(costs), len(path), rarity)
            self.assertEqual(list(costs), sorted(costs), "never cheaper later")

    def test_speed(self):
        speed = SHARED["speed"]
        self.assertEqual(rules.SPEED_SETUP_SECONDS, speed["setup_seconds"])
        self.assertEqual(list(rules.SPEED_DAY_SECONDS), speed["day_seconds"])
        self.assertEqual(rules.SPEED_LAST_PROMPT_DAY, speed["last_prompt_day"])
        for count in range(rules.MIN_PLAYERS, rules.MAX_PLAYERS + 1):
            self.assertEqual(
                [p.value for p in rules.speed_prompts_for(count)],
                speed["setup"][str(count)],
            )
            drawn = [
                (a.prompt, a.subject)
                for artist in range(count)
                for a in rules.speed_assignments_for(count, artist)
            ]
            # Everyone is drawn twice: once as a basic, once as another.
            for subject in range(count):
                prompts = [p for p, s in drawn if s == subject]
                self.assertEqual(len(prompts), 2, (count, subject))
                self.assertIn(rules.SetupPrompt.BASIC, prompts)
            self.assertNotIn(
                rules.SetupPrompt.ALTER, [p for p, _ in drawn], "no alter to base on"
            )

    def test_themes(self):
        self.assertEqual([t.value for t in rules.Theme], SHARED["themes"])
        # One per weekday, from Monday (2026-10-05) to Sunday.
        week = [rules.theme_of_date(date(2026, 10, 5 + i)) for i in range(7)]
        self.assertEqual(week, list(rules.Theme))
        self.assertEqual(rules.theme_of_date(date(2026, 10, 12)), rules.Theme.FOREST)

    def test_fights(self):
        fights = SHARED["fights"]
        self.assertEqual(rules.MAX_FIGHTERS, fights["max_fighters"])
        self.assertEqual(rules.CHALLENGER_STARS, fights["challenger_stars"])
        for team, boost_stars, fighters_win in fights["cases"]:
            self.assertEqual(
                rules.fighters_win(
                    rules.team_stars([rules.Rarity(r) for r in team]), boost_stars
                ),
                fighters_win,
                (team, boost_stars),
            )

    def test_boost(self):
        boost = SHARED["boost"]
        self.assertEqual(rules.BOOST_CHALLENGERS, boost["challengers"])
        self.assertEqual(rules.BOOST_STARS, boost["stars"])
        self.assertEqual(rules.BOOST_MAX_PER_CHALLENGER, boost["max_per_challenger"])

    def test_hurry(self):
        hurry = SHARED["hurry"]
        self.assertEqual(rules.HURRY_CUT_FRACTION, hurry["cut_fraction"])
        self.assertEqual(rules.CHALLENGER_DRAW_SECONDS, SHARED["challenger_draw_seconds"])
        self.assertEqual(
            (rules.HURRY_EARLIEST, rules.HURRY_LATEST),
            (hurry["earliest"], hurry["latest"]),
        )
