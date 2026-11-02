"""Win rates: after each week, a player's characters get extra stars this
week against the players whose characters they beat most of the time last
week.

A character counts for the player it depicts. In a fight, every fighter
meets the challenger once: the side that won the fight wins that meeting,
and fighters depicting the challenger's own player don't count. A player who
won more than a share of at least `rules.WIN_RATE_MIN_FIGHTS` meetings with
another player's characters last week gets `rules.win_rate_extra_stars`:
each of their fighters gets them against a challenger of that player, and a
challenger of theirs gets them for each fighter of that player. Speed mode
sessions have no weeks, so no win rates.
"""

import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session, aliased

from app import days, rules, speed
from app.models import Character, Fight, Fighter, Server, ServerSeat


@dataclass(frozen=True)
class Record:
    """How `player`'s characters did against `against`'s last week."""

    player: uuid.UUID
    against: uuid.UUID
    fights: int
    wins: int

    @property
    def extra_stars(self) -> int:
        return rules.win_rate_extra_stars(self.wins, self.fights)


def counted_week(server: Server, day: int) -> tuple[int, int]:
    """The first and last day of the week before `day`'s, whose fights give
    the win rates of `day`'s week."""
    start = days.week_start(server, day)
    return start - 7, start - 1


def records(session: Session, server: Server, day: int) -> list[Record]:
    """Every player's record against every other player in the week before
    `day`'s, both ways, by roster order. Its fights must be decided
    (`app.fights.complete_fights`, `app.fights.decide_fights`)."""
    if speed.is_speed(server):
        return []
    first, last = counted_week(server, day)
    fighter = aliased(Character)
    challenger = aliased(Character)
    meetings = session.execute(
        select(fighter.subject_seat_id, challenger.subject_seat_id, Fight.fighters_win)
        .select_from(Fighter)
        .join(Fight, Fight.id == Fighter.fight_id)
        .join(fighter, fighter.id == Fighter.character_id)
        .join(challenger, challenger.id == Fight.challenger_id)
        .where(
            challenger.server_id == server.id,
            Fight.day >= first,
            Fight.day <= last,
            Fight.fighters_win.is_not(None),
            fighter.subject_seat_id != challenger.subject_seat_id,
        )
    ).all()
    fights: dict[tuple[uuid.UUID, uuid.UUID], int] = {}
    wins: dict[tuple[uuid.UUID, uuid.UUID], int] = {}
    for fighter_player, challenger_player, fighters_win in meetings:
        winner, loser = (
            (fighter_player, challenger_player)
            if fighters_win
            else (challenger_player, fighter_player)
        )
        for pair in ((winner, loser), (loser, winner)):
            fights[pair] = fights.get(pair, 0) + 1
        wins[(winner, loser)] = wins.get((winner, loser), 0) + 1
    order = {s.id: s.position for s in server.seats}
    return [
        Record(player, against, n, wins.get((player, against), 0))
        for (player, against), n in sorted(
            fights.items(), key=lambda item: (order[item[0][0]], order[item[0][1]])
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
