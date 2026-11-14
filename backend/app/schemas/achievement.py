from pydantic import BaseModel


class AchievementResponse(BaseModel):
    """One of your achievements (`app.achievements`) and its reward."""

    # Names it, e.g. "artist:2" or "wins:3"; collect it by it.
    key: str
    # "artist", "portrait", "rarity", "wins" or "streak".
    kind: str
    # The player of an artist or portrait achievement, by roster position.
    player_position: int | None
    # The rarity of a rarity achievement.
    rarity: str | None
    goal: int
    progress: int
    stars: int
    done: bool
    collected: bool
