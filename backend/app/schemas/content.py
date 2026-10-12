import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.rules import Theme


class ContentItem(BaseModel):
    """A prompt hint or a premade title in use."""

    id: uuid.UUID
    theme: Theme
    text: str
    # It's used from the day after.
    created_at: datetime


class ContentAdd(BaseModel):
    """Hints or premade titles to add to a theme."""

    theme: Theme
    texts: list[str] = Field(min_length=1, max_length=200)


class ContentAdded(BaseModel):
    added: list[ContentItem]
    # Left out: the theme has them already (ignoring case), or they came twice.
    skipped: list[str]
