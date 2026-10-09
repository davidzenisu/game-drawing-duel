from pydantic import BaseModel, Field

from app.schemas.character import CharacterResponse


class GachaResponse(BaseModel):
    """Your pulls and pity progress."""

    tickets: int
    total_pulls: int
    # Pulls left until a legend is guaranteed.
    pulls_until_legend: int
    # Pulls left within the beginner window, or null once it no longer applies.
    beginner_pulls_left: int | None


class PullRequest(BaseModel):
    count: int = Field(ge=1, le=10)


class PullOutcomeResponse(BaseModel):
    character: CharacterResponse
    # Pulled for the first time.
    is_new: bool
    # How many you own now.
    copies: int


class PullsResponse(BaseModel):
    outcomes: list[PullOutcomeResponse]
    gacha: GachaResponse


class OwnedCharacterResponse(BaseModel):
    character: CharacterResponse
    copies: int
