from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, StringConstraints, field_validator

from app.rules import MAX_PLAYERS, MIN_PLAYERS

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


class ServerResponse(BaseModel):
    code: str
    created_at: datetime
    is_test: bool
    is_admin: bool
    # Your seat, or null if you haven't joined (yet).
    your_position: int | None
    seats: list[SeatResponse]
