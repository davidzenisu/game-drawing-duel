import uuid
from datetime import date

from pydantic import BaseModel


class AdminDrawing(BaseModel):
    """A drawing of a server, for admins to look at: a setup drawing (no
    `day`) or a day's challenger."""

    id: uuid.UUID
    # The day a challenger was drawn and the calendar day (UTC) it was
    # played on; both null for the initial setup drawings.
    day: int | None
    date: date | None
    artist: str
    subject: str
    title: str
    rarity: str
    prompt: str
