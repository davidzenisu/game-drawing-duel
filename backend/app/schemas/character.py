import uuid
from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints, model_validator

from app.rules import MAX_TITLE_LENGTH

# Points are normalised to the canvas, see `Stroke` in the frontend.
Coordinate = Annotated[float, Field(ge=0, le=1)]

# Generous limits a drawing never reaches, to keep the files small.
MAX_STROKES = 5_000
MAX_POINTS = 200_000


class StrokeData(BaseModel):
    # ARGB, e.g. 0xFF000000 for black.
    color: int = Field(ge=0, le=0xFFFFFFFF)
    # Relative to the canvas width.
    width: float = Field(gt=0, le=0.25)
    # x and y of every point, one after the other.
    points: list[Coordinate] = Field(min_length=2)

    @model_validator(mode="after")
    def _check_pairs(self) -> "StrokeData":
        if len(self.points) % 2:
            raise ValueError("points must be pairs of x and y")
        return self


class SketchData(BaseModel):
    strokes: list[StrokeData] = Field(min_length=1, max_length=MAX_STROKES)

    @model_validator(mode="after")
    def _check_size(self) -> "SketchData":
        if sum(len(s.points) for s in self.strokes) > 2 * MAX_POINTS:
            raise ValueError("The drawing has too many points")
        return self


Title = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=MAX_TITLE_LENGTH),
]


class DrawingSubmit(BaseModel):
    title: Title
    sketch: SketchData


class CharacterResponse(BaseModel):
    """A drawn character; its sketch is at `/characters/{id}/sketch`."""

    id: uuid.UUID
    title: str
    # An `app.rules.Rarity`.
    rarity: str
    prompt: str
    artist_position: int
    subject_position: int
