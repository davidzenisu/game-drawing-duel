from pydantic import BaseModel


class PlacedPlayer(BaseModel):
    """A player's value of a stat and their place: tied players share one."""

    player_position: int
    value: int
    place: int


class PlayerStat(BaseModel):
    """A player stat (`app.player_stats`), every player who joined ranked."""

    # "stars-earned", "hot-streak", "most-wins", "best-artist",
    # "giant-slayer", "most-boosts" or "busiest".
    key: str
    players: list[PlacedPlayer]


class PlayerStatsResponse(BaseModel):
    """How the players did from `from_day` to `to_day`, a stat at a time."""

    # "week" (the ongoing one), "last-week" (the latest finished one) or
    # "all" (all time).
    period: str
    from_day: int
    to_day: int
    # The stars each first place got once the week was over; 0 for the
    # ongoing week and all time.
    reward_stars: int
    stats: list[PlayerStat]
