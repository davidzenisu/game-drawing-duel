import uuid

from pydantic import BaseModel, Field

from app.schemas.character import CharacterResponse


class ArenaStatus(BaseModel):
    """The Arena open today, as you see it (`app.arena`)."""

    # The Arena: the last day of its challengers' week, and the last day to
    # vote in it.
    week: int
    ends_on: int
    # How many challengers it holds.
    challengers: int
    # Your votes today, and the most you can cast today.
    votes_today: int
    cap: int
    # The votes today's stars take (the pack, or the cap if lower), and the
    # stars they earn.
    pack: int
    pack_stars: int
    # Whether today's pack earned its stars already.
    rewarded: bool


class ArenaResponse(BaseModel):
    """Your Arena today; null fields when there's none (the first week,
    speed mode)."""

    status: ArenaStatus | None = None
    # The next matchup to vote on, shown in this order; null at the cap or
    # without pairs left.
    matchup: list[CharacterResponse] | None = None
    # The one after it, to show below it; null if the next is today's last
    # vote. Voting on it next works too.
    next_matchup: list[CharacterResponse] | None = None
    # Your stars, with today's pack reward once earned.
    stars: int = 0


class ArenaVoteSubmit(BaseModel):
    # The matchup's two challengers.
    challenger_ids: list[uuid.UUID] = Field(min_length=2, max_length=2)
    # The better one; null for a draw ("can't decide").
    winner_id: uuid.UUID | None = None


class ArenaHeroResponse(BaseModel):
    """A winner of the latest Arena, now in the gacha pool with the rarity it
    was crowned with (its character's)."""

    character: CharacterResponse
    # The Arena: the last day of its challengers' week.
    week: int
    # Its place in the Arena's ranking, 1 to 3.
    place: int


class ArenaRanked(BaseModel):
    character: CharacterResponse
    # Its place: the winners' first, by place, then the others'.
    place: int
    # The `app.rules.Rarity` it was crowned with as an Arena winner; null if
    # it wasn't.
    hero_rarity: str | None = None
    # Its rating (`app.rules.arena_ratings`), its score in its matchups (a
    # draw counts a half) and how many.
    rating: float
    score: float
    matchups: int
    # Whether it took part in enough matchups to be ranked
    # (`app.rules.ARENA_MIN_MATCHUPS`); the others come last, unranked.
    qualified: bool = True


class ArenaRankingResponse(BaseModel):
    """The latest decided Arena, best first; its winners joined the gacha
    pool."""

    # The last day of its challengers' week, and of its week of votes.
    week: int
    ends_on: int
    # The matchups a challenger needs to be ranked, and crowned.
    min_matchups: int
    challengers: list[ArenaRanked]
