import uuid
from datetime import datetime

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, utc_now


class ArenaVote(Base):
    """A player's vote on an Arena matchup (`app.arena`): which of two of
    the week before's challengers is the better drawing, or a draw ("can't
    decide"). A player votes on each pair once."""

    __tablename__ = "arena_vote"
    __table_args__ = (UniqueConstraint("voter_seat_id", "first_id", "second_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    server_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server.id", ondelete="CASCADE"), nullable=False, index=True
    )
    voter_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    # The Arena: the last day of its challengers' week (their finale's day).
    week: Mapped[int] = mapped_column(Integer, nullable=False)
    # The day the vote was cast on, for the daily pack and cap.
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    # The pair, in a fixed order (by id), so each pair is one row.
    first_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False
    )
    second_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False
    )
    # The better one; null for a draw.
    winner_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE")
    )
    voted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )
