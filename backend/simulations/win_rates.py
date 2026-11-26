"""Simulates Arena weeks to choose the win rate thresholds (#299).

Win rates come from the Arena's votes: a vote for a challenger portraying
one player over one portraying another is a meeting the first player won.
This plays whole Arenas with the Arena's own pair picking
(`app.arena._matchups`) and daily cap (`rules.arena_daily_cap`), counts
their meetings with `app.win_rates.meetings` under candidate rules, and
compares each pair of players' share of the meetings with the share they
deserve: how often, over every matchup of their drawings in the Arena, all
the voters together would pick theirs, without the noise of a single vote,
of which pairs got shown, or of voters favouring their own portraits. Extra
stars should go to pairs that deserve them ("earned"), and seldom to the
ones that clearly don't ("luck").

Run from `backend/`:

    uv run python -m simulations.win_rates [--weeks N] [--players 5 7 10]

Model, per simulated week:

- Every player draws a challenger a day for a week, each portraying another
  player, at random; the finale takes 3 of them, at random, so the Arena
  holds the rest.
- Each drawing has a quality, normal around 0. Voters share most of their
  taste: each sees a drawing's quality plus a taste of their own (`TASTE`),
  and picks the one they like more, with logistic noise (`SHARPNESS`); when
  it's close, they can't decide half the time (a draw).
- A voter likes the drawings portraying themselves a bit more (`SELF`).
- Each voter votes the daily pack, some days more (`DAILY_VOTES`), up to
  the daily cap.
"""

import argparse
import math
import random
import statistics
import uuid
from dataclasses import dataclass
from types import SimpleNamespace

from app import arena, rules, win_rates

CHALLENGERS_PER_PLAYER = 7
WEEKLY_HEROES = 3
TASTE = 0.5
SHARPNESS = 2.0
SELF = 0.5
# Below this difference in what a voter sees, they can't decide half the
# time.
CLOSE = 0.15
# How many votes a voter casts on a day, at random: the pack, some more.
DAILY_VOTES = (10, 10, 10, 20, 40)
# A pair "clearly doesn't deserve" a band below its share by this much.
MARGIN = 0.1

RULES = (
    # (votes a voter's meetings count on a pair of players, own portraits)
    (None, True),
    (10, True),
    (5, True),
    (None, False),
)
MINIMUMS = (10, 15, 20, 30)
SHARES = (0.6, 0.65, 0.7, 0.75, 0.8)


def _beats(diff: float) -> float:
    return 1 / (1 + math.exp(-SHARPNESS * diff))


@dataclass(frozen=True)
class Week:
    players: int
    # Every (voter, winner's player, loser's player) of the week's decisive
    # votes, in the order cast.
    votes: list[tuple[int, int, int]]
    # The share each ordered pair of players deserves.
    deserved: dict[tuple[int, int], float]


def simulate_week(players: int, rng: random.Random) -> Week:
    seats = [
        SimpleNamespace(id=uuid.UUID(int=rng.getrandbits(128))) for _ in range(players)
    ]
    entries = []
    quality = {}
    subject_of = {}
    for artist in range(players):
        for _ in range(CHALLENGERS_PER_PLAYER):
            subject = rng.choice([p for p in range(players) if p != artist])
            c = SimpleNamespace(
                id=uuid.UUID(int=rng.getrandbits(128)),
                artist_seat_id=seats[artist].id,
                subject_seat_id=seats[subject].id,
            )
            entries.append(c)
            quality[c.id] = rng.gauss(0, 1)
            subject_of[c.id] = subject
    rng.shuffle(entries)
    entries = entries[WEEKLY_HEROES:]
    taste = {(v, c.id): rng.gauss(0, TASTE) for v in range(players) for c in entries}

    def seen(v: int, c: SimpleNamespace) -> float:
        return quality[c.id] + taste[(v, c.id)]

    # Every voter's chance to pick a over b, over every matchup of two
    # players' drawings, without favouring their own portraits.
    totals: dict[tuple[int, int], list[float]] = {}
    for a in entries:
        for b in entries:
            p, q = subject_of[a.id], subject_of[b.id]
            if p == q:
                continue
            totals.setdefault((p, q), []).append(
                statistics.fmean(
                    _beats(seen(v, a) - seen(v, b)) for v in range(players)
                )
            )
    deserved = {pair: statistics.fmean(chances) for pair, chances in totals.items()}

    server = SimpleNamespace(id=uuid.UUID(int=rng.getrandbits(128)))
    votes: list[SimpleNamespace] = []
    decisive: list[tuple[int, int, int]] = []
    pairs = {v: len(arena._pairs(entries, seats[v])) for v in range(players)}
    cast = dict.fromkeys(range(players), 0)
    for day in range(1, arena.DAYS + 1):
        for v in rng.sample(range(players), players):
            seat = seats[v]
            cap = rules.arena_daily_cap(pairs[v] - cast[v], arena.DAYS - day + 1)
            count = min(cap, rng.choice(DAILY_VOTES))
            for a, b in arena._matchups(server, seat, day, entries, votes, count):
                diff = seen(v, a) - seen(v, b)
                diff += SELF * ((subject_of[a.id] == v) - (subject_of[b.id] == v))
                first, second = arena._pair(a.id, b.id)
                winner = None
                if abs(diff) >= CLOSE or rng.random() < 0.5:
                    winner, loser = (a, b) if rng.random() < _beats(diff) else (b, a)
                    decisive.append((v, subject_of[winner.id], subject_of[loser.id]))
                votes.append(
                    SimpleNamespace(
                        voter_seat_id=seat.id,
                        first_id=first,
                        second_id=second,
                        winner_id=None if winner is None else winner.id,
                        day=day,
                    )
                )
                cast[v] += 1
    return Week(players, decisive, deserved)


def counted(week: Week, per_voter: int | None, own: bool):
    """Every ordered pair of players' (wins, meetings, deserved share)."""
    records = win_rates.meetings(
        [
            (voter, winner, loser)
            for voter, winner, loser in week.votes
            if own or voter not in (winner, loser)
        ],
        per_voter,
    )
    return [(wins, n, week.deserved[pair]) for pair, (wins, n) in records.items()]


def report(players: int, weeks: list[Week]) -> None:
    pairs = players * (players - 1) * len(weeks)
    print(f"\n## {players} players, {len(weeks)} weeks")
    print(
        f"Decisive votes a week: {statistics.mean(len(w.votes) for w in weeks):.0f}; "
        f"pairs of players deserving a share of at least "
        + ", ".join(
            f"{round(s * 100)}%: "
            f"{sum(d >= s for w in weeks for d in w.deserved.values()) / pairs:.1%}"
            for s in SHARES
        )
    )
    for per_voter, own in RULES:
        print(
            f"\n### Per voter and pair of players: {per_voter or 'all'}; "
            f"own portraits {'count' if own else 'left out'}"
        )
        rows = [r for w in weeks for r in counted(w, per_voter, own)]
        sizes = sorted(n for _, n, _ in rows)
        print(
            f"Meetings per pair: 10th percentile {sizes[len(sizes) // 10]}, "
            f"median {statistics.median(sizes):.0f}, max {sizes[-1]}"
        )
        print("| min | " + " | ".join(f"{round(s * 100)}%" for s in SHARES) + " |")
        print("|---" * (len(SHARES) + 1) + "|")
        for minimum in MINIMUMS:
            cells = []
            for share in SHARES:
                reached = [
                    d
                    for wins, n, d in rows
                    if n >= minimum and wins * 100 >= round(share * 100) * n
                ]
                deserving = sum(d >= share for w in weeks for d in w.deserved.values())
                earned = sum(d >= share for d in reached) / max(1, deserving)
                luck = sum(d < share - MARGIN for d in reached) / max(1, len(reached))
                cells.append(
                    f"{len(reached) / pairs:.0%} get it, earned {earned:.0%}, "
                    f"luck {luck:.0%}"
                )
            print(f"| {minimum} | " + " | ".join(cells) + " |")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--weeks", type=int, default=50)
    parser.add_argument("--seed", type=int, default=299)
    parser.add_argument("--players", type=int, nargs="*", default=[5, 7, 10])
    args = parser.parse_args()
    rng = random.Random(args.seed)
    for players in args.players:
        report(players, [simulate_week(players, rng) for _ in range(args.weeks)])


if __name__ == "__main__":
    main()
