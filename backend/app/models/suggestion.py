import uuid
from datetime import datetime

from sqlalchemy import (
    DateTime,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, utc_now


class Suggestion(Base):
    """An idea or a bug report a player posted on their server's feedback
    board. Only the players of the same server see it, and upvote it."""

    __tablename__ = "suggestion"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    server_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server.id", ondelete="CASCADE"), nullable=False, index=True
    )
    author_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    # "idea" or "bug".
    kind: Mapped[str] = mapped_column(String(10), nullable=False)
    title: Mapped[str] = mapped_column(String(80), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    votes: Mapped[list[SuggestionVote]] = relationship(
        back_populates="suggestion", cascade="all, delete-orphan"
    )


class SuggestionVote(Base):
    """A seat's upvote of a suggestion: one each, never the author's own."""

    __tablename__ = "suggestion_vote"
    __table_args__ = (UniqueConstraint("suggestion_id", "seat_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    suggestion_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("suggestion.id", ondelete="CASCADE"), nullable=False
    )
    seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    voted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    suggestion: Mapped[Suggestion] = relationship(back_populates="votes")
