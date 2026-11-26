"""Win rates: after each week, a player's characters get extra stars this
week against the players whose portraits won most of their Arena matchups
against theirs last week.

A challenger counts for the player it portrays. In the Arena voted on last
week (`app.arena`, on the challengers of the week before), a vote for a
challenger portraying one player over one portraying another is a meeting
the first player won. Draws ("can't decide") and matchups of two portraits
of the same player count for nothing, and each voter's first
`rules.WIN_RATE_MATCHUPS_PER_VOTER` votes on a pair of players count, so no
one voter swings it. A player who won at least a share of at least
`rules.WIN_RATE_MIN_MATCHUPS` meetings with another player gets
`rules.win_rate_extra_stars`: each of their fighters gets them against a
challenger of that player, and a challenger of theirs gets them for each
fighter of that player. The fights themselves don't count. Until the first
Arena is over (a server's third week) there are none; speed mode sessions
have no weeks, so no Arena and no win rates.
"""

import uuid
from collections import Counter
from dataclasses import dataclass

from sqlalchemy import case, select
from sqlalchemy.orm import Session, aliased

from app import days, rules, speed
from app.models import ArenaVote, Character, Server, ServerSeat


@dataclass(frozen=True)
class Record:
    """How `player`'s portraits did against `against`'s in last week's
    Arena: the meetings counted, and how many `player` won."""

    player: uuid.UUID
    against: uuid.UUID
    matchups: int
    wins: int

    @property
    def extra_stars(self) -> int:
        return rules.win_rate_extra_stars(self.wins, self.matchups)


def meetings[P](
    votes: list[tuple[object, P, P]], per_voter: int | None
) -> dict[tuple[P, P], tuple[int, int]]:
    """Every pair of players' (wins, meetings), both ways, from `votes` of
    (voter, winner's player, loser's player) in the order cast: each voter's
    first `per_voter` on a pair of players count (all without a cap). Votes
    between two portraits of the same player count for nothing."""
    cast: Counter[tuple[object, frozenset]] = Counter()
    result: dict[tuple[P, P], tuple[int, int]] = {}
    for voter, winner, loser in votes:
        if winner == loser:
            continue
        key = (voter, frozenset((winner, loser)))
        if per_voter is not None and cast[key] >= per_voter:
            continue
        cast[key] += 1
        wins, n = result.get((winner, loser), (0, 0))
        result[(winner, loser)] = (wins + 1, n + 1)
        wins, n = result.get((loser, winner), (0, 0))
        result[(loser, winner)] = (wins, n + 1)
    return result


def counted_week(server: Server, day: int) -> tuple[int, int]:
    """The first and last day of the week before `day`'s, whose Arena votes
    give the win rates of `day`'s week."""
    start = days.week_start(server, day)
    return start - 7, start - 1


def arena_week(server: Server, day: int) -> int:
    """The Arena whose votes give the win rates of `day`'s week: the one
    voted on during the week before (`app.arena`), on the challengers of the
    week before that."""
    return days.week_start(server, day) - 8


def records(session: Session, server: Server, day: int) -> list[Record]:
    """Every player's record against every other player in the Arena voted
    on in the week before `day`'s, both ways, by roster order."""
    if speed.is_speed(server):
        return []
    winner = aliased(Character)
    loser = aliased(Character)
    votes = session.execute(
        select(
            ArenaVote.voter_seat_id,
            winner.subject_seat_id,
            loser.subject_seat_id,
        )
        .join(winner, winner.id == ArenaVote.winner_id)
        .join(
            loser,
            loser.id
            == case(
                (ArenaVote.winner_id == ArenaVote.first_id, ArenaVote.second_id),
                else_=ArenaVote.first_id,
            ),
        )
        .where(
            ArenaVote.server_id == server.id,
            ArenaVote.week == arena_week(server, day),
        )
        .order_by(ArenaVote.voted_at, ArenaVote.id)
    ).all()
    counted = meetings([tuple(v) for v in votes], rules.WIN_RATE_MATCHUPS_PER_VOTER)
    order = {s.id: s.position for s in server.seats}
    return [
        Record(player, against, n, wins)
        for (player, against), (wins, n) in sorted(
            counted.items(), key=lambda item: (order[item[0][0]], order[item[0][1]])
        )
    ]


def extra_stars(
    session: Session, server: Server, day: int
) -> dict[tuple[uuid.UUID, uuid.UUID], int]:
    """The extra stars a player's characters get against another player's on
    `day`, by (player, against); pairs without any are left out."""
    return {
        (r.player, r.against): r.extra_stars
        for r in records(session, server, day)
        if r.extra_stars
    }


@dataclass(frozen=True)
class FightExtraStars:
    challenger: int
    # By fighter, in the order given.
    fighters: list[int]


def for_fight(
    session: Session,
    seat: ServerSeat,
    day: int,
    challenger: Character,
    fighters: list[Character],
) -> FightExtraStars:
    """The extra stars of both sides of a fight on `day`."""
    extra = extra_stars(session, seat.server, day)
    against = challenger.subject_seat_id
    return FightExtraStars(
        challenger=sum(extra.get((against, f.subject_seat_id), 0) for f in fighters),
        fighters=[extra.get((f.subject_seat_id, against), 0) for f in fighters],
    )
