"""Checks that the fight rules keep fights close: the challengers should win
about half of them."""

import random
import unittest

from app import rules
from app.gacha import RATES

DAYS = 2000


def _spread(rng: random.Random, targets: int) -> list[int]:
    """A player's boost stars, spread at random like chance does."""
    stars = [0] * targets
    for _ in range(rules.BOOST_STARS):
        open_ = [i for i, n in enumerate(stars) if n < rules.BOOST_MAX_PER_CHALLENGER]
        stars[rng.choice(open_)] += 1
    return stars


def fighters_win_rate(players: int, rng: random.Random) -> float:
    """The share of fights won by teams of four fighters rolled at the gacha
    rates, against challengers everyone boosted at random. Everyone boosts
    the challengers of the players the same offsets on, like
    `app.fights.boost_targets`."""
    rarities, weights = list(RATES), list(RATES.values())
    targets = min(rules.BOOST_CHALLENGERS, players - 2)
    wins = 0
    for _ in range(DAYS):
        boosts = [0] * players
        for player in range(players):
            for offset, stars in enumerate(_spread(rng, targets), 1):
                boosts[(player + offset) % players] += stars
        for boost_stars in boosts:
            team = rng.choices(rarities, weights, k=rules.MAX_FIGHTERS)
            wins += rules.fighters_win(rules.team_stars(team), boost_stars)
    return wins / (DAYS * players)


class BalanceTest(unittest.TestCase):
    def test_challengers_win_about_half_the_fights(self):
        rng = random.Random(1)
        for players in range(rules.MIN_PLAYERS, rules.MAX_PLAYERS + 1):
            rate = fighters_win_rate(players, rng)
            # Full teams win a bit more; weekly rests make teams weaker.
            self.assertTrue(0.4 <= rate <= 0.65, f"{players} players: {rate:.0%}")
