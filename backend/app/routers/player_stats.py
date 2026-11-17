"""How every player did, a stat at a time, see `app.player_stats`."""

from enum import StrEnum

from fastapi import APIRouter, HTTPException, status

from app import days, fights, finale, player_stats, speed
from app.auth import CurrentPlayer
from app.deps import Code, DbSession, running_game
from app.rules import STARS_FOR_WEEK_STAT
from app.schemas import PlacedPlayer, PlayerStat, PlayerStatsResponse

router = APIRouter(prefix="/servers", tags=["player stats"])


class Period(StrEnum):
    WEEK = "week"
    LAST_WEEK = "last-week"
    ALL = "all"


@router.get("/{code}/player-stats", response_model=PlayerStatsResponse | None)
def get_player_stats(
    code: Code, player: CurrentPlayer, session: DbSession, period: Period = Period.WEEK
) -> PlayerStatsResponse | None:
    """Every player's stats, each a ranking of all players: in the ongoing
    week (up to today), the latest finished week (null before the first is
    over; its first places got `reward_stars` each) or all time. Speed mode
    sessions have none."""
    server, _ = running_game(session, code, player.id)
    if speed.is_speed(server):
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="Speed mode has no player stats"
        )
    today = days.current_day(server)
    finale.settle(session, server)
    reward = 0
    if period is Period.LAST_WEEK:
        week = finale.latest_finale(session, server)
        if week is None:
            return None
        first, last, reward = (
            days.week_start(server, week.day),
            week.day,
            STARS_FOR_WEEK_STAT,
        )
    else:
        # The boosts and fights nobody finished yesterday count too.
        fights.complete_boosts(session, server, today - 1)
        fights.complete_fights(session, server, today - 1)
        first = days.week_start(server, today) if period is Period.WEEK else 1
        last = today
    values = player_stats.values(session, server, first, last)
    return PlayerStatsResponse(
        period=period.value,
        from_day=max(first, 1),
        to_day=last,
        reward_stars=reward,
        stats=[
            PlayerStat(
                key=stat,
                players=[
                    PlacedPlayer(
                        player_position=p.seat.position, value=p.value, place=p.place
                    )
                    for p in player_stats.ranking(server, values[stat])
                ],
            )
            for stat in player_stats.STATS
        ],
    )
