from pydantic import BaseModel

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


class TodayResponse(BaseModel):
    day: int
    # An `app.rules.Theme`.
    theme: str
    prompt: YourPrompt
    to_draw: PromptToDrawResponse | None
    # Test sessions: the seats that ended the day. Empty on regular servers.
    day_ended: list[int]
