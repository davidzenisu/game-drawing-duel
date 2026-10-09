import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, StringConstraints, field_validator

from app.rules import MAX_PLAYERS, MIN_PLAYERS
from app.schemas.character import CharacterResponse

SeatName = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50)
]


class ServerCreate(BaseModel):
    """The other players; the admin takes the first seat themselves."""

    other_names: list[SeatName]
    is_test: bool = False

    @field_validator("other_names")
    @classmethod
    def _check_count(cls, names: list[str]) -> list[str]:
        if not MIN_PLAYERS - 1 <= len(names) <= MAX_PLAYERS - 1:
            raise ValueError(
                f"A server has {MIN_PLAYERS} to {MAX_PLAYERS} players including you"
            )
        return names


class SeatResponse(BaseModel):
    position: int
    name: str
    joined: bool
    # Finished their setup drawings.
    setup_done: bool


class ServerResponse(BaseModel):
    code: str
    created_at: datetime
    is_test: bool
    is_admin: bool
    # "lobby" while players join, "setup" once the admin started the setup,
    # "running" once everyone finished their setup drawings.
    phase: Literal["lobby", "setup", "running"]
    # Your seat, or null if you haven't joined (yet).
    your_position: int | None
    seats: list[SeatResponse]


class AssignmentResponse(BaseModel):
    """A drawing you make during the initial setup."""

    id: uuid.UUID
    # An `app.rules.SetupPrompt`.
    prompt: str
    # The seat of the player to draw.
    subject_position: int
    # The assignment this one builds on (the alter is based on the basic).
    based_on: uuid.UUID | None
    # Your drawing for it, once submitted.
    character: CharacterResponse | None
