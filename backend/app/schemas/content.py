import uuid
from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints

from app.rules import MAX_TITLE_LENGTH, Theme

Text = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]
Title = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=MAX_TITLE_LENGTH),
]


class ContentItem(BaseModel):
    """A prompt hint in use: a description and the premade title that stands
    in if the player who got it writes none."""

    id: uuid.UUID
    theme: Theme
    text: str
    premade_title: str
    # It's used from the day after.
    created_at: datetime


class HintDraft(BaseModel):
    text: Text
    premade_title: Title


class ContentAdd(BaseModel):
    """Hints to add to a theme."""

    theme: Theme
    hints: list[HintDraft] = Field(min_length=1, max_length=200)


class ContentAdded(BaseModel):
    added: list[ContentItem]
    # Descriptions left out: the theme has them already (ignoring case), or
    # they came twice.
    skipped: list[str]
