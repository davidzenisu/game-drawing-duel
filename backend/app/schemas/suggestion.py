import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, StringConstraints

SuggestionKind = Literal["idea", "bug"]
# Open by default; server admins set it to in progress, rejected or in
# review, and its author to done once in review.
SuggestionStatus = Literal["open", "in_progress", "rejected", "in_review", "done"]
# The statuses server admins can pick: done is up to the author.
SettableStatus = Literal["open", "in_progress", "rejected", "in_review"]


class SuggestionSubmit(BaseModel):
    """An idea or a bug report for your server's feedback board."""

    kind: SuggestionKind
    title: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)
    ]
    description: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)
    ]


class SuggestionStatusChange(BaseModel):
    """A server admin's new status for a suggestion."""

    status: SettableStatus


class SuggestionResponse(BaseModel):
    """A suggestion on the board, as you see it."""

    id: uuid.UUID
    kind: SuggestionKind
    title: str
    description: str
    status: SuggestionStatus
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
