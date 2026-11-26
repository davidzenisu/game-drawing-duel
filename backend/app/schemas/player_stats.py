from pydantic import BaseModel

from app.schemas.day import BoostBalanceResponse


class PlacedPlayer(BaseModel):
    """A player's value of a stat and their place (tied players share one),
    both null while the stat is secret; and the trophies they won in it so
    far."""

    player_position: int
    value: int | None
    place: int | None
    trophies: int


class PlayerStat(BaseModel):
    """A player stat (`app.player_stats`), every player who joined ranked."""

    # "most-wins", "most-boosted" or "busy-streak".
    key: str
    # Hidden until the week is over: the players come in roster order.
    secret: bool
    players: list[PlacedPlayer]


class PortrayedPlayer(BaseModel):
    """How many of the week's challengers portray a player."""

    player_position: int
    challengers: int


class PlayerStatsResponse(BaseModel):
    """How the players did from `from_day` to `to_day`, a stat at a time."""

    # "week" (the ongoing one) or "last-week" (the latest finished one).
    period: str
    from_day: int
    to_day: int
    # The stars of each trophy, won by the first places once the week is over.
    trophy_stars: int
    stats: list[PlayerStat]
    # Every player of the roster, with the challengers portraying them of the
    # ones the week ranks (fought that week), drawn so far; their stars stay
    # out.
    portrayed: list[PortrayedPlayer]
    # The ongoing week only: its boost stars, the ones its challengers are
    # boosted with, and why; null in the first week.
    boost_balance: BoostBalanceResponse | None = None
