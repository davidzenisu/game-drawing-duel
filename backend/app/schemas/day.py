import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.rules import BOOST_CHALLENGERS, BOOST_MAX_PER_CHALLENGER, MAX_FIGHTERS
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


class OutcomeResponse(BaseModel):
    """The stars decide: the fighters win with more than the challenger."""

    # The fighters' stars: their rarities' (upgrades don't count yet).
    fighter_stars: int
    # The challenger's boost stars, and its stars with them.
    boost_stars: int
    challenger_stars: int
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


class BoostStep(BaseModel):
    """Step 3: spread your boost stars across a few of yesterday's
    challengers, never the one you drew or the one you fight tomorrow. Change
    them all day; once it's over, chance spreads the stars you left."""

    targets: list[BoostTarget]
    # The stars you spread, and how many one challenger takes at most.
    stars: int
    max_per_challenger: int


class FightStep(BaseModel):
    """Step 4: the challenger you pick fighters against today. Its stars stay
    secret until you picked them."""

    challenger: CharacterResponse
    # Your fighters and how they fared, once picked.
    yours: FightResponse | None
    # Your characters that fought earlier this week: every character but the
    # basic ones fights once a week, they're back on Monday (UTC).
    resting: list[uuid.UUID]


class IncomingHurry(BaseModel):
    """Someone cut your challenger drawing time today: by
    `rules.HURRY_CUT_FRACTION` of the time left when it hits."""

    by_position: int
    # When it hits, as a fraction of the time limit.
    at_fraction: float


class WeeklyHeroResponse(BaseModel):
    """The latest finale's winner, now in the gacha pool."""

    character: CharacterResponse
    # The finale day it won on: the last day of its week.
    day: int
    # Its own stars plus its boost stars.
    stars: int


class RankedChallenger(BaseModel):
    character: CharacterResponse
    # Its own stars plus its boost stars.
    stars: int
    # Its fights by the end of the week, and how many of them it won.
    fights: int
    wins: int


class RankingResponse(BaseModel):
    """The latest finished week's challengers, most stars first; the first
    joined the gacha pool as a hero."""

    # The last day of the week.
    day: int
    challengers: list[RankedChallenger]


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
    boost: BoostStep | None
    # Yesterday's fights you picked the fighters for (or chance did), or
    # drew the challenger of.
    results: list[FightResponse]
    # The seat you sent today's free hurry to.
    hurry_sent_to: int | None
    # Every hurry sent to you today, for your challenger drawing, in the
    # order they hit.
    incoming_hurries: list[IncomingHurry]
    # Test sessions: the seats that ended the day. Empty on regular servers.
    day_ended: list[int]
    weekly_hero: WeeklyHeroResponse | None


class ChallengerResponse(BaseModel):
    """A challenger you encountered and how it fared."""

    character: CharacterResponse
    # Its decided fights, and how many of them it won.
    fights: int
    wins: int


class FightersSubmit(BaseModel):
    character_ids: list[uuid.UUID] = Field(min_length=1, max_length=MAX_FIGHTERS)


class BoostGiven(BaseModel):
    challenger_id: uuid.UUID
    stars: int = Field(ge=0, le=BOOST_MAX_PER_CHALLENGER)


class BoostSubmit(BaseModel):
    # Replaces the stars you gave today.
    boosts: list[BoostGiven] = Field(max_length=BOOST_CHALLENGERS)


class HurrySubmit(BaseModel):
    target_position: int
