import uuid
from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints

from app.rules import SERVER_CODE_LENGTH

# The most pulls one gift gives each player.
MAX_GIFT_PULLS = 100


class GiftResponse(BaseModel):
    """A gift waiting for you to accept it: its pulls count once you do."""

    id: uuid.UUID
    message: str
    pulls: int
    sent_at: datetime


class GiftSend(BaseModel):
    """A gift to send: to everyone on every server without `server_code`,
    else to everyone on that server, or only the seats at `positions`."""

    message: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)
    ]
    pulls: int = Field(ge=1, le=MAX_GIFT_PULLS)
    server_code: str | None = Field(
        default=None, pattern=rf"^\d{{{SERVER_CODE_LENGTH}}}$"
    )
    positions: list[int] | None = None


class GiftSent(BaseModel):
    id: uuid.UUID
    # How many players got it.
    recipients: int


class AdminPlayer(BaseModel):
    position: int
    name: str
    # Whether a player joined this seat yet.
    joined: bool


class AdminServer(BaseModel):
    """A server that wasn't cancelled, with its players, for sending gifts."""

    code: str
    speed: bool
    launched: bool
    players: list[AdminPlayer]
