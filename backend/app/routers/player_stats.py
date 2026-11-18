"""How every player did in a week, a stat at a time, see
`app.player_stats`."""

from enum import StrEnum

from fastapi import APIRouter, HTTPException, status

from app import days, fights, finale, player_stats, speed
from app.auth import CurrentPlayer
from app.deps import Code, DbSession, running_game
from app.rules import STARS_FOR_WEEK_STAT
from app.schemas import (
    PlacedPlayer,
    PlayerStat,
    PlayerStatsResponse,
    PortrayedPlayer,
)

router = APIRouter(prefix="/servers", tags=["player stats"])


class Period(StrEnum):
    WEEK = "week"
    LAST_WEEK = "last-week"


@router.get("/{code}/player-stats", response_model=PlayerStatsResponse | None)
def get_player_stats(
    code: Code, player: CurrentPlayer, session: DbSession, period: Period = Period.WEEK
) -> PlayerStatsResponse | None:
    """Every player's stats, each a ranking of all players with their
    trophies so far, and who the week's challengers portray: in the ongoing
    week (up to today; the secret ones without values) or the latest
    finished week (null before the first is over). Speed mode sessions have
    none."""
    server, _ = running_game(session, code, player.id)
    if speed.is_speed(server):
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="Speed mode has no player stats"
        )
    today = days.current_day(server)
    finale.settle(session, server)
    if period is Period.LAST_WEEK:
        week = finale.latest_finale(session, server)
        if week is None:
            return None
        first, last = days.week_start(server, week.day), week.day
    else:
        # The boosts and fights nobody finished yesterday count too.
        fights.complete_boosts(session, server, today - 1)
        fights.complete_fights(session, server, today - 1)
        first, last = days.week_start(server, today), today
    values = player_stats.values(session, server, first, last)
    trophies = player_stats.trophies(session, server)
    portrayed = player_stats.portrayed(session, server, first + 6)

    def stat(key: str) -> PlayerStat:
        won = trophies.get(key, {})
        if period is Period.WEEK and key in player_stats.SECRET:
            return PlayerStat(
                key=key,
                secret=True,
                players=[
                    PlacedPlayer(
                        player_position=s.position,
                        value=None,
                        place=None,
                        trophies=won.get(s.id, 0),
                    )
                    for s in days.active_seats(server)
                ],
            )
        return PlayerStat(
            key=key,
            secret=False,
            players=[
                PlacedPlayer(
                    player_position=p.seat.position,
                    value=p.value,
                    place=p.place,
                    trophies=won.get(p.seat.id, 0),
                )
                for p in player_stats.ranking(server, values[key])
            ],
        )

    return PlayerStatsResponse(
        period=period.value,
        from_day=max(first, 1),
        to_day=last,
        trophy_stars=STARS_FOR_WEEK_STAT,
        stats=[stat(key) for key in player_stats.STATS],
        portrayed=[
            PortrayedPlayer(
                player_position=s.position, challengers=portrayed.get(s.id, 0)
            )
            for s in sorted(server.seats, key=lambda s: s.position)
        ],
    )
