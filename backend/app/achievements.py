"""Achievements: goals each player reaches on their own, each rewarded once
with stars they collect (`collect`). Progress is worked out from the game
itself, nothing is stored but the collected rewards: a `StarGrant` whose
reason is `achievement:<key>`.

- `artist:<position>`: own every starter hero (setup drawing) drawn by
  another player. Your own drawings are yours from the start.
- `portrait:<position>`: own every starter hero portraying a player, you
  included.
- `rarity:<rarity>`: own every starter hero of a rarity.
- `wins:<n>`: win n fights you picked the fighters for (chance's wins earn
  nothing, as everywhere).
- `streak:<n>`: win n of those fights in a row; a lost one starts over,
  days without one of your own fights don't.
"""

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import pulls, stars
from app.models import Character, Fight, Server, ServerSeat, StarGrant
from app.rules import (
    ACHIEVEMENT_FIGHT_STARS,
    ACHIEVEMENT_PLAYER_STARS,
    ACHIEVEMENT_RARITY_STARS,
    ACHIEVEMENT_STREAKS,
    ACHIEVEMENT_WINS,
    Rarity,
)

REASON_PREFIX = "achievement:"


@dataclass(frozen=True)
class Achievement:
    key: str
    # "artist", "portrait", "rarity", "wins" or "streak".
    kind: str
    # The player of an artist or portrait achievement.
    position: int | None
    # The rarity of a rarity achievement.
    rarity: Rarity | None
    goal: int
    # Towards the goal, at most the goal.
    progress: int
    stars: int
    collected: bool

    @property
    def done(self) -> bool:
        return self.progress >= self.goal


def player_stars(server: Server) -> int:
    """The reward of an artist or portrait achievement: fewer players, more
    stars."""
    players = len(server.seats)
    lowest, highest = min(ACHIEVEMENT_PLAYER_STARS), max(ACHIEVEMENT_PLAYER_STARS)
    return ACHIEVEMENT_PLAYER_STARS[min(max(players, lowest), highest)]


def _wins_and_best_streak(session: Session, seat: ServerSeat) -> tuple[int, int]:
    """How many of the fights `seat` picked the fighters for it won, and the
    most it won in a row."""
    outcomes = session.scalars(
        select(Fight.fighters_win)
        .where(
            Fight.owner_seat_id == seat.id,
            Fight.by_chance.is_(False),
            Fight.fighters_win.is_not(None),
        )
        .order_by(Fight.day)
    ).all()
    wins = best = streak = 0
    for won in outcomes:
        streak = streak + 1 if won else 0
        wins += won
        best = max(best, streak)
    return wins, best


def of(session: Session, server: Server, seat: ServerSeat) -> list[Achievement]:
    """`seat`'s achievements: the players' first (artists, then portraits),
    then the rarities, the wins and the streaks."""
    owned = set(pulls.copies(session, seat))
    starters = session.scalars(
        select(Character).where(
            Character.server_id == server.id, Character.assignment_id.is_not(None)
        )
    ).all()
    collected = set(
        session.scalars(
            select(StarGrant.reason).where(
                StarGrant.seat_id == seat.id,
                StarGrant.reason.like(f"{REASON_PREFIX}%"),
            )
        )
    )

    entries: list[Achievement] = []

    def add(
        key: str,
        kind: str,
        goal: int,
        progress: int,
        reward: int,
        position: int | None = None,
        rarity: Rarity | None = None,
    ) -> None:
        entries.append(
            Achievement(
                key=key,
                kind=kind,
                position=position,
                rarity=rarity,
                goal=goal,
                progress=min(progress, goal),
                stars=reward,
                collected=f"{REASON_PREFIX}{key}" in collected,
            )
        )

    def add_set(
        key: str, kind: str, heroes: list[Character], reward: int, **about
    ) -> None:
        # Only sets with heroes in them: a player who drew nothing has none.
        if heroes:
            owned_ones = sum(c.id in owned for c in heroes)
            add(key, kind, len(heroes), owned_ones, reward, **about)

    reward = player_stars(server)
    for other in sorted(server.seats, key=lambda s: s.position):
        if other.id == seat.id:
            continue
        drawn = [c for c in starters if c.artist_seat_id == other.id]
        add_set(f"artist:{other.position}", "artist", drawn, reward, position=other.position)
    for subject in sorted(server.seats, key=lambda s: s.position):
        portraits = [c for c in starters if c.subject_seat_id == subject.id]
        add_set(
            f"portrait:{subject.position}",
            "portrait",
            portraits,
            reward,
            position=subject.position,
        )
    for rarity, rarity_reward in ACHIEVEMENT_RARITY_STARS.items():
        of_rarity = [c for c in starters if c.rarity == rarity.value]
        add_set(f"rarity:{rarity.value}", "rarity", of_rarity, rarity_reward, rarity=rarity)
    wins, best = _wins_and_best_streak(session, seat)
    for n in ACHIEVEMENT_WINS:
        add(f"wins:{n}", "wins", n, wins, ACHIEVEMENT_FIGHT_STARS)
    for n in ACHIEVEMENT_STREAKS:
        add(f"streak:{n}", "streak", n, best, ACHIEVEMENT_FIGHT_STARS)
    return entries


class CantCollect(Exception):
    pass


def collect(session: Session, server: Server, seat: ServerSeat, key: str) -> None:
    """Collects the stars of `seat`'s achievement `key`, once it's done.
    Collecting again changes nothing. Commits."""
    achievement = next((a for a in of(session, server, seat) if a.key == key), None)
    if achievement is None:
        raise CantCollect("No such achievement")
    if not achievement.done:
        raise CantCollect("Not achieved yet")
    if achievement.collected:
        return
    session.add(stars.grant(seat.id, f"{REASON_PREFIX}{key}", achievement.stars))
    try:
        session.commit()
    except IntegrityError:
        session.rollback()  # Collected at the same time elsewhere.

