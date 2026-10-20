import uuid

from pydantic import BaseModel, Field

from app.gacha import Banner
from app.rules import Element
from app.schemas.character import CharacterResponse


class GachaResponse(BaseModel):
    """Your pulls and pity progress."""

    tickets: int
    total_pulls: int
    # Pulls left until a legend is guaranteed.
    pulls_until_legend: int
    # Standard banner pulls left within the beginner window, or null once it
    # no longer applies.
    beginner_pulls_left: int | None
    # This week's rate-up characters on the weekly banner, see
    # `app.pulls.rate_up`; none until the first finale, and no weekly banner.
    rate_up: list[uuid.UUID] = []


class PullRequest(BaseModel):
    count: int = Field(ge=1, le=10)
    # The weekly banner opens with the first finale.
    banner: Banner = Banner.STANDARD


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
    # Unlocked upgrades in path order (`app.rules.UpgradeEffect`).
    upgrades: list[str]
    # The element chosen for the element upgrade, if unlocked.
    element: str | None


class UpgradeRequest(BaseModel):
    """Only needed when the next upgrade is the element."""

    element: Element | None = None
