import uuid

from pydantic import BaseModel, Field

from app.rules import MAX_FIGHTERS
from app.schemas.character import CharacterResponse


class YourPrompt(BaseModel):
    """Step 1: the challenger title you write today."""

    subject_position: int
    # What you wrote, or null.
    title: str | None


class PromptToDrawResponse(BaseModel):
    """Step 2: the prompt you draw today, from the day before."""

    author_position: int
    subject_position: int
    title: str
    # An `app.rules.Theme`.
    theme: str
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
    fighter_votes: int
    challenger_votes: int
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
    # What you voted, or null.
    your_vote: bool | None
    # Once the voting day is over: the votes, including the ones decided by
    # chance for everyone who didn't vote.
    outcome: OutcomeResponse | None


class FightStep(BaseModel):
    """Step 3: the challenger you pick fighters against today."""

    challenger: CharacterResponse
    # Your fighters, once picked.
    yours: FightResponse | None


class TodayResponse(BaseModel):
    day: int
    # An `app.rules.Theme`.
    theme: str
    prompt: YourPrompt
    to_draw: PromptToDrawResponse | None
    fight: FightStep | None
    # Step 4: yesterday's fights you vote on.
    to_vote: list[FightResponse]
    # Decided fights you picked the fighters for, or drew the challenger of.
    results: list[FightResponse]
    # Test sessions: the seats that ended the day. Empty on regular servers.
    day_ended: list[int]


class FightersSubmit(BaseModel):
    character_ids: list[uuid.UUID] = Field(min_length=1, max_length=MAX_FIGHTERS)


class VoteSubmit(BaseModel):
    fighters_win: bool
