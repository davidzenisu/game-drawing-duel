"""Game rules the server enforces.

The frontend implements the same rules (`frontend/lib/game/rules`); both are
checked against `shared/rules.json`.
"""

import random
from dataclasses import dataclass
from datetime import date
from enum import StrEnum
from fractions import Fraction

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

# After a fight, a character rests this many days before it can fight again:
# with 1, a character that fought on Monday rests on Tuesday and is back on
# Wednesday.
REST_DAYS = {
    Rarity.BASIC: 1,
    Rarity.ADVENTURER: 2,
    Rarity.HERO: 3,
    Rarity.LEGEND: 4,
}

# Every day, a player spreads boost stars across this many of the day
# before's challengers, all of them on one at most: this many in the first
# week and in speed mode, then balanced week by week (`boost_balance_step`).
BOOST_CHALLENGERS = 3
BOOST_STARS = 3

# Each week starts from the week before's boost stars and changes them by
# the heroes' share of the week before's decided fights, once there were at
# least this many: winning more than a share of `MORE` gives that many more
# stars (the most of every share beaten), less than a share of `FEWER` that
# many fewer (the most of every share undercut). Never fewer than the
# minimum or more than the maximum.
BOOST_BALANCE_MIN_FIGHTS = 7
BOOST_BALANCE_MORE = ((0.6, 1), (0.8, 2))
BOOST_BALANCE_FEWER = ((0.4, 1), (0.2, 2))
BOOST_MIN_STARS = 3
BOOST_MAX_STARS = 6


def boost_balance_step(hero_wins: int, fights: int) -> int:
    """How many boost stars more (or fewer) a week gives after the heroes
    won `hero_wins` of the week before's `fights`."""
    if fights < BOOST_BALANCE_MIN_FIGHTS:
        return 0
    more = max(
        (n for share, n in BOOST_BALANCE_MORE if hero_wins > share * fights),
        default=0,
    )
    fewer = max(
        (n for share, n in BOOST_BALANCE_FEWER if hero_wins < share * fights),
        default=0,
    )
    return more - fewer


def balanced_boost_stars(previous: int, step: int) -> int:
    """A week's boost stars: the week before's changed by `step`, within
    the minimum and maximum."""
    return min(BOOST_MAX_STARS, max(BOOST_MIN_STARS, previous + step))


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


# The weekly finale (`app.finale`) crowns the top 3 of the week's ranking as
# weekly heroes: 1st place a legend, 2nd a hero, 3rd an adventurer.
FINALE_RARITIES = (Rarity.LEGEND, Rarity.HERO, Rarity.ADVENTURER)
FINALE_MAX_HEROES = len(FINALE_RARITIES)


@dataclass(frozen=True)
class FinaleEntry:
    """What a week's challenger is ranked by."""

    # Who drew it: any value that tells artists apart.
    artist: object
    boost_stars: int
    # The boost stars all of its artist's challengers ranked that week got.
    artist_boost_stars: int
    wins: int
    fights: int
    # The day it was drawn.
    day: int


def finale_order(entries: list[FinaleEntry]) -> list[int]:
    """The indexes of a week's challengers, best first, picked one place at
    a time: the most boost stars, then one whose artist has no drawing
    ranked above it yet, then the most boost stars its artist's challengers
    got that week, then the best win rate (none without fights), then the
    latest day it was drawn, then the first in `entries`."""

    def key(i: int) -> tuple:
        e = entries[i]
        win_rate = Fraction(e.wins, e.fights) if e.fights else Fraction(0)
        return (
            -e.boost_stars,
            e.artist in ranked_artists,
            -e.artist_boost_stars,
            -win_rate,
            -e.day,
            i,
        )

    left = list(range(len(entries)))
    ranked_artists: set[object] = set()
    order = []
    while left:
        best = min(left, key=key)
        left.remove(best)
        order.append(best)
        ranked_artists.add(entries[best].artist)
    return order


# The Arena (`app.arena`): every player votes on matchups of two of the week
# before's challengers that the finale didn't crown. Once the week of votes
# is over, the top 3 by their rating are crowned Arena winners, with the
# finale's rarities by place.
ARENA_RARITIES = FINALE_RARITIES
# A day's first matchups earn these stars once all are voted on; voting goes
# on after them, unrewarded, up to the day's cap (`arena_daily_cap`).
ARENA_PACK = 10
ARENA_PACK_STARS = 3
# Each challenger also draws once against a virtual one of strength 1, so
# ratings stay finite and one without votes sits in the middle.
ARENA_PRIOR_DRAWS = 1
# A challenger takes part in this many matchups at least to be ranked, and
# crowned; the others are left unranked. All votes count for the ratings,
# also the ones against those left out.
ARENA_MIN_MATCHUPS = 5


def arena_daily_cap(pairs_left: int, days_left: int) -> int:
    """How many matchups a player can vote on today, with `pairs_left` pairs
    they haven't voted on at the start of the day and `days_left` days of the
    Arena, today included: as many as they like, as long as a pack's pairs
    stay for every day after today, so the daily stars never run out before
    the Arena ends; but always the pack while pairs are left."""
    if pairs_left <= 0 or days_left <= 0:
        return 0
    spare = pairs_left - ARENA_PACK * (days_left - 1)
    return min(pairs_left, max(ARENA_PACK, spare))


def arena_ratings(
    count: int, matchups: list[tuple[int, int, float]], iterations: int = 500
) -> list[float]:
    """The Bradley–Terry strengths of `count` challengers from `matchups` of
    (i, j, i's score: 1 a win, 0.5 a draw, 0 a loss), computed from all of
    them at once, so their order doesn't matter. Each challenger also has
    `ARENA_PRIOR_DRAWS` draws against a virtual one of strength 1."""
    wins = [ARENA_PRIOR_DRAWS * 0.5] * count
    opponents: list[list[int]] = [[] for _ in range(count)]
    for i, j, score in matchups:
        wins[i] += score
        wins[j] += 1 - score
        opponents[i].append(j)
        opponents[j].append(i)
    strengths = [1.0] * count
    for _ in range(iterations):
        new = [
            wins[i]
            / (
                ARENA_PRIOR_DRAWS / (strengths[i] + 1)
                + sum(1 / (strengths[i] + strengths[j]) for j in opponents[i])
            )
            for i in range(count)
        ]
        done = all(abs(n - s) <= 1e-12 * max(s, 1) for n, s in zip(new, strengths))
        strengths = new
        if done:
            break
    return strengths


def arena_order(count: int, matchups: list[tuple[int, int, float]]) -> list[int]:
    """The indexes of an Arena's challengers, best first: the ones with at
    least `ARENA_MIN_MATCHUPS` matchups before the others, then the highest
    rating (`arena_ratings`, from all of the matchups), then the first in the
    list (the challengers come in the order of their week's ranking)."""
    ratings = arena_ratings(count, matchups)
    taken = arena_matchups(count, matchups)
    return sorted(
        range(count),
        key=lambda i: (taken[i] < ARENA_MIN_MATCHUPS, -round(ratings[i], 9), i),
    )


def arena_matchups(count: int, matchups: list[tuple[int, int, float]]) -> list[int]:
    """How many of `matchups` each of `count` challengers took part in."""
    taken = [0] * count
    for i, j, _ in matchups:
        taken[i] += 1
        taken[j] += 1
    return taken


def arena_qualified(matchups: int) -> bool:
    """Whether a challenger with that many matchups is ranked, and can be
    crowned."""
    return matchups >= ARENA_MIN_MATCHUPS


# A player's characters get extra stars against another player's after
# winning at least a share (in whole percent) of last week's fights against
# them: the most extra stars of every share they reach. It takes this many
# fights to count.
WIN_RATE_MIN_FIGHTS = 3
WIN_RATE_EXTRA_STARS = ((0.8, 1),)

# The boost balance and the win rate bands above start with the week of this
# Monday (UTC), so running servers switch between two weeks instead of in the
# middle of one. The weeks before keep `BOOST_STARS` a day and these bands.
BALANCE_FROM = date(2026, 11, 23)
WIN_RATE_EXTRA_STARS_BEFORE = ((0.5, 1), (0.75, 2))


def win_rate_extra_stars(
    wins: int,
    fights: int,
    bands: tuple[tuple[float, int], ...] = WIN_RATE_EXTRA_STARS,
) -> int:
    """The extra stars for winning `wins` of `fights` last week, by `bands`
    of [share, extra stars]: the most of every share reached. Shares count
    in whole percent, so 4 of 5 reaches 80%."""
    if fights < WIN_RATE_MIN_FIGHTS:
        return 0
    return max(
        (stars for share, stars in bands if wins * 100 >= round(share * 100) * fights),
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
# The longest short message a hurry's sender can add.
HURRY_MESSAGE_MAX_LENGTH = 60

# Stars, the currency players collect (`app.stars`): writing a challenger
# title and drawing a challenger earn these; a won fight earns the
# challenger's stars.
STARS_FOR_PROMPT = 3
STARS_FOR_CHALLENGER = 3
# Stars buy a pull for this many, any time.
STARS_PER_PULL = 10
# Once a week is over, the first place of each player stat (`app.player_stats`)
# wins a trophy worth these stars, as a gift; tied first places each win one.
STARS_FOR_WEEK_STAT = 3

# Achievements (`app.achievements`), each rewarded once with stars:
# - owning every starter hero of another player's, or portraying a player,
#   by the number of players in the roster (fewer is harder);
ACHIEVEMENT_PLAYER_STARS = {5: 10, 6: 9, 7: 8, 8: 7, 9: 6, 10: 5}
# - owning every starter hero of a rarity;
ACHIEVEMENT_RARITY_STARS = {
    Rarity.BASIC: 10,
    Rarity.ADVENTURER: 15,
    Rarity.LEGEND: 20,
}
# - winning this many fights you picked the fighters for, this many of them
#   in a row, and this many of them by exactly one star (close calls), each
#   level worth the same.
ACHIEVEMENT_WINS = (1, 3, 5, 10, 25, 50)
ACHIEVEMENT_STREAKS = tuple(range(3, 26))
ACHIEVEMENT_CLOSE_CALLS = (1, 3, 5, 10, 25, 50)
ACHIEVEMENT_FIGHT_STARS = 5
# A speed mode session has no levels above this one: it has no more fights
# of your own.
ACHIEVEMENT_SPEED_MAX_GOAL = 3


def hurry_hits(jitters: list[float]) -> list[float]:
    """The seconds left at which each of a day's hurries hits, in the order
    they were sent, from a random share in [0, 1) each (its jitter).

    They're spread evenly: the window's time not taken by the cuts of the
    hurries before is split into one stretch per hurry, and each hits
    somewhere in its own, so together they never run past the last moment."""
    n = len(jitters)
    room = max(
        0.0,
        HURRY_FIRST_LEFT_SECONDS
        - HURRY_LAST_LEFT_SECONDS
        - (n - 1) * HURRY_CUT_SECONDS,
    )
    return [
        HURRY_FIRST_LEFT_SECONDS - i * HURRY_CUT_SECONDS - room / n * (i + jitter)
        for i, jitter in enumerate(jitters)
    ]
