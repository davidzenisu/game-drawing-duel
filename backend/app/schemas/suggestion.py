import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, StringConstraints

SuggestionKind = Literal["idea", "bug"]


class SuggestionSubmit(BaseModel):
    """An idea or a bug report for your server's feedback board."""

    kind: SuggestionKind
    title: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)
    ]
    description: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)
    ]


class SuggestionResponse(BaseModel):
    """A suggestion on the board, as you see it."""

    id: uuid.UUID
    kind: SuggestionKind
    title: str
    description: str
    # The author's name on the server.
    author: str
    created_at: datetime
    votes: int
    # Whether you upvoted it.
    voted: bool
    # Whether you wrote it: you can't upvote your own.
    yours: bool
    # Whether you can remove it: your own, or any for server admins.
    removable: bool
