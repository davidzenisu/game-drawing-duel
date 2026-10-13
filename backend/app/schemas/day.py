import uuid

from pydantic import BaseModel, Field

from app.rules import MAX_FIGHTERS
from app.schemas.character import CharacterResponse


class YourPrompt(BaseModel):
    """Step 1: the person you choose for today's description, and the title
    you write for them."""

    # The description to choose a person and write a title for, or null if
    # there's none.
    hint: str | None
    # The challenger's `app.rules.Theme`: the theme of the day its heroes are
    # picked, two days from now.
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
    # How many players boosted the challenger, and its stars with the boosts.
    boosts: int
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
    # Once the boosting day is over: the stars of both sides.
    outcome: OutcomeResponse | None


class BoostTarget(BaseModel):
    """Step 4: one of yesterday's challengers you may boost, with the teams
    that were sent against it."""

    challenger: CharacterResponse
    matchups: list[FightResponse]


class FightStep(BaseModel):
    """Step 3: the challenger you pick fighters against today."""

    challenger: CharacterResponse
    # Your fighters, once picked.
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


class TodayResponse(BaseModel):
    day: int
    # An `app.rules.Theme`.
    theme: str
    prompt: YourPrompt
    to_draw: PromptToDrawResponse | None
    fight: FightStep | None
    # Step 4: yesterday's challengers you may boost, all but the one you drew
    # and the one you fought, and the one you boosted today if you did.
    to_boost: list[BoostTarget]
    boosted: uuid.UUID | None
    # Decided fights you picked the fighters for, or drew the challenger of.
    results: list[FightResponse]
    # The seat you sent today's free hurry to.
    hurry_sent_to: int | None
    # Every hurry sent to you today, for your challenger drawing, in the
    # order they hit.
    incoming_hurries: list[IncomingHurry]
    # Test sessions: the seats that ended the day. Empty on regular servers.
    day_ended: list[int]


class ChallengerResponse(BaseModel):
    """A challenger you encountered and how it fared."""

    character: CharacterResponse
    # Its decided fights, and how many of them it won.
    fights: int
    wins: int


class FightersSubmit(BaseModel):
    character_ids: list[uuid.UUID] = Field(min_length=1, max_length=MAX_FIGHTERS)


class BoostSubmit(BaseModel):
    challenger_id: uuid.UUID


class HurrySubmit(BaseModel):
    target_position: int
