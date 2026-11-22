import uuid
from datetime import date, datetime
from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints

from app.rules import (
    BOOST_CHALLENGERS,
    BOOST_MAX_STARS,
    HURRY_MESSAGE_MAX_LENGTH,
    MAX_FIGHTERS,
)
from app.schemas.character import CharacterResponse


class YourPrompt(BaseModel):
    """Step 1: the person you choose for today's description, and the title
    you write for them."""

    # The description to choose a person and write a title for, or null if
    # there's none.
    hint: str | None
    # The challenger's `app.rules.Theme`: the theme of the day it's fought,
    # three days from now.
    theme: str
    # Who you chose and what you wrote, or null.
    subject_position: int | None
    title: str | None


class PromptToDrawResponse(BaseModel):
    """Step 2: the prompt you draw today, from the day before."""

    author_position: int
    subject_position: int
    title: str
    # An `app.rules.Theme`.
    theme: str
    # The description the author chose the person and wrote the title for,
    # or the one a premade title came with; null if they got none.
    hint: str | None
    # Nobody wrote it: a premade title stands in.
    premade: bool
    # What you drew, or null.
    challenger: CharacterResponse | None


class FighterResponse(BaseModel):
    character: CharacterResponse
    # The upgrades it had when it was sent in (`app.rules.UpgradeEffect`).
    upgrades: list[str]
    element: str | None
    # Its extra stars from its player's win rate against the challenger's.
    extra_stars: int


class OutcomeResponse(BaseModel):
    """The stars decide: the fighters win with more than the challenger,
    each side with its win rate extra stars."""

    # The fighters' stars: their rarities' (upgrades don't count yet).
    fighter_stars: int
    # The challenger's boost stars, and its stars with them.
    boost_stars: int
    challenger_stars: int
    # Both sides' extra stars from their players' win rates of last week
    # (`GET /servers/{code}/win-rates`): the fighters' all together.
    fighter_extra_stars: int
    challenger_extra_stars: int
    # Ties go to the challenger.
    fighters_win: bool


class FightResponse(BaseModel):
    id: uuid.UUID
    # The day the fighters were picked.
    day: int
    owner_position: int
    challenger: CharacterResponse
    fighters: list[FighterResponse]
    # The owner picked nobody, so chance did.
    by_chance: bool
    # The stars of both sides: decided as soon as the fighters are picked.
    outcome: OutcomeResponse


class BoostTarget(BaseModel):
    """One of yesterday's challengers you may boost, and the stars you gave
    it."""

    challenger: CharacterResponse
    stars: int


class BoostBalanceResponse(BaseModel):
    """A week's boost stars a day, and why: the week before's, changed by
    the heroes' share of its decided fights (`app.boost_balance`)."""

    # The first and last day of the week before, whose fights count.
    from_day: int
    to_day: int
    # Its decided fights, and how many the heroes won.
    fights: int
    hero_wins: int
    # The fights it takes to change the stars.
    min_fights: int
    # The week before's boost stars, the change its fights give, and the
    # week's stars within the minimum and maximum.
    previous_stars: int
    step: int
    stars: int


class BoostStep(BaseModel):
    """Step 3: spread your boost stars across a few of yesterday's
    challengers, never the one you drew or the one you fight tomorrow. Change
    them all day; once it's over, chance spreads the stars you left."""

    targets: list[BoostTarget]
    # The stars you spread, and how many one challenger takes at most.
    stars: int
    max_per_challenger: int
    # Why this week has `stars`; null in the first week and in speed mode.
    balance: BoostBalanceResponse | None = None


class FightStep(BaseModel):
    """Step 4: the challenger you pick fighters against today. Its stars stay
    secret until you picked them."""

    challenger: CharacterResponse
    # Your fighters and how they fared, once picked.
    yours: FightResponse | None


class IncomingHurry(BaseModel):
    """Someone cut your challenger drawing time today: by
    `rules.HURRY_CUT_SECONDS` when it hits."""

    by_position: int
    # When it hits: the drawing time left then, in seconds.
    left_seconds: float
    # The sender's short message, if they added one.
    message: str | None = None


class WeeklyHeroResponse(BaseModel):
    """A hero of the latest finale, now in the gacha pool with the rarity it
    was crowned with (its character's)."""

    character: CharacterResponse
    # The finale day it was crowned on: the last day of its week.
    day: int
    # Its own stars plus its boost stars.
    stars: int
    # Its place in the week's ranking, 1 to 3.
    place: int


class RankedBoost(BaseModel):
    """Boost stars a player gave a ranked challenger."""

    booster_position: int
    stars: int
    # Spread by chance, from the stars the player didn't give themselves.
    by_chance: bool


class RankedFight(BaseModel):
    """A fight of a ranked challenger: who fought it, and whether it won."""

    player_position: int
    challenger_won: bool


class RankedChallenger(BaseModel):
    character: CharacterResponse
    # Its own stars plus its boost stars.
    stars: int
    # Its place in the ranking (`app.rules.finale_key`); a weekly hero's
    # is the one it was crowned with.
    place: int
    # The boost stars all of its artist's challengers ranked that week got,
    # its own included: the ranking's first tiebreak.
    artist_boost_stars: int = 0
    # The `app.rules.Rarity` it was crowned with as a weekly hero; null if
    # it wasn't (always in speed mode).
    hero_rarity: str | None = None
    # Its fights by the end of the week, and how many of them it won.
    fights: int
    wins: int
    # Who wrote its prompt: the player before its artist. `default_prompt`
    # if they wrote none, so it was drawn from a premade title.
    prompt_author_position: int | None = None
    default_prompt: bool = False
    # Its boosts, by player: theirs and the ones chance spread for them.
    boosts: list[RankedBoost] = []
    # Its fights by the end of the week.
    fought_by: list[RankedFight] = []


class RankingResponse(BaseModel):
    """The latest finished week's challengers, most stars first; its weekly
    heroes joined the gacha pool."""

    # The last day of the week.
    day: int
    challengers: list[RankedChallenger]
    # The boost stars its fights gave the week after; null in speed mode.
    boost_balance: BoostBalanceResponse | None = None


class TodayResponse(BaseModel):
    day: int
    # An `app.rules.Theme`.
    theme: str
    # Speed mode: when today ends, at the latest.
    ends_at: datetime | None = None
    # Null on days without challenger prompts (the last days of a speed mode
    # session).
    prompt: YourPrompt | None
    to_draw: PromptToDrawResponse | None
    fight: FightStep | None
    # Your characters that rest after a fight (`rules.REST_DAYS`), with how
    # many days each still rests from today on: 1 is back tomorrow. Today's
    # fighters count too: they rest from tomorrow on, so their rest days plus
    # one. Sent every day, with a fight step or not.
    rest_days: dict[uuid.UUID, int]
    boost: BoostStep | None
    # You skipped yesterday's drawing, so you can't boost today.
    boost_forfeited: bool = False
    # Yesterday's fights you picked the fighters for (or chance did), or
    # drew the challenger of.
    results: list[FightResponse]
    # The seat you sent today's free hurry to; it hits their drawing
    # tomorrow.
    hurry_sent_to: int | None
    # The short message you added to it, if any.
    hurry_message: str | None = None
    # Every hurry sent to you yesterday, for today's challenger drawing, in
    # the order they hit.
    incoming_hurries: list[IncomingHurry]
    # Test sessions: the seats that ended the day. Empty on regular servers.
    day_ended: list[int]
    # The latest finale's heroes, by place; empty before the first finale
    # and after a week without any.
    weekly_heroes: list[WeeklyHeroResponse] = []


class ChallengerResponse(BaseModel):
    """A challenger you encountered and how it fared."""

    character: CharacterResponse
    # Its decided fights, and how many of them it won.
    fights: int
    wins: int
    # For its artist: the stars it won in its fights, to collect, and the
    # ones collected already.
    stars_to_collect: int = 0
    stars_collected: int = 0


class FightersSubmit(BaseModel):
    character_ids: list[uuid.UUID] = Field(min_length=1, max_length=MAX_FIGHTERS)


class BoostGiven(BaseModel):
    challenger_id: uuid.UUID
    stars: int = Field(ge=0, le=BOOST_MAX_STARS)


class BoostSubmit(BaseModel):
    # Replaces the stars you gave today.
    boosts: list[BoostGiven] = Field(max_length=BOOST_CHALLENGERS)


HurryMessage = Annotated[
    str,
    StringConstraints(strip_whitespace=True, max_length=HURRY_MESSAGE_MAX_LENGTH),
]


class HurrySubmit(BaseModel):
    target_position: int
    # An optional short message, shown to the target when it hits; blank is
    # none.
    message: HurryMessage | None = None


class WinRate(BaseModel):
    """How a player's characters did against another player's last week, and
    the extra stars that gives them against that player this week."""

    player_position: int
    against_position: int
    # The fighters and challengers of both that met, and how many of those
    # meetings `player_position` won.
    fights: int
    wins: int
    extra_stars: int


class WinRatesResponse(BaseModel):
    """This week's win rates, from last week's fights: every fighter meets
    the challenger once, and characters count for the player they depict."""

    # The first and last day of the week whose fights count.
    from_day: int
    to_day: int
    # The meetings it takes for a win rate to give extra stars, and the
    # extra stars for winning more than a share of them: [share, stars].
    min_fights: int
    extra_stars: list[tuple[float, int]]
    # Every pair of players whose characters met, both ways.
    win_rates: list[WinRate]


class FightDay(BaseModel):
    """A past day with fights to replay."""

    day: int
    # The calendar day (UTC) it fell on.
    date: date
