import uuid
from datetime import datetime

from sqlalchemy import (
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, utc_now
from app.models.character import Character


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


class ArenaHero(Base):
    """An Arena winner, crowned once its Arena's week of votes is over: the
    top `rules.ARENA_RARITIES` of its ranking join the server's gacha pool,
    each with the rarity of its place (`app.arena`). An Arena without
    challengers has one row without a character (`character_id` null), so
    it counts as decided."""

    __tablename__ = "arena_hero"
    __table_args__ = (
        # One row without a character for an Arena without winners.
        UniqueConstraint(
            "server_id", "week", "character_id", postgresql_nulls_not_distinct=True
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    server_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server.id", ondelete="CASCADE"), nullable=False
    )
    # The Arena: the last day of its challengers' week. It's voted on the
    # week after and decided once that one is over.
    week: Mapped[int] = mapped_column(Integer, nullable=False)
    character_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), unique=True
    )
    # Its place in the Arena's ranking, 1 to 3.
    place: Mapped[int | None] = mapped_column(Integer)
    # The `app.rules.Rarity` it was crowned with, now the character's.
    rarity: Mapped[str | None] = mapped_column(String(20))
    # Its rating (`rules.arena_ratings`) and its matchups: its score in them
    # (a draw counts a half) and how many.
    rating: Mapped[float | None] = mapped_column(Float)
    score: Mapped[float | None] = mapped_column(Float)
    matchups: Mapped[int | None] = mapped_column(Integer)
    decided_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    character: Mapped[Character | None] = relationship()
