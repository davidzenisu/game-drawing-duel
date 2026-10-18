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
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, utc_now
from app.models.character import Character


class FinaleVote(Base):
    """Step 5, on the last day of a week: a seat picked one of two of the
    week's winning challengers. Each vote adds a star to the one picked.

    The pair is stored in a fixed order (`first_id` < `second_id`), so a seat
    votes on every pair once at most."""

    __tablename__ = "finale_vote"
    __table_args__ = (UniqueConstraint("voter_seat_id", "first_id", "second_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    voter_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    # The finale day: the last day (Sunday) of the week.
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    first_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False
    )
    second_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False
    )
    chosen_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False, index=True
    )
    voted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )


class WeeklyHero(Base):
    """A week's finale, decided once the week is over: the challenger with
    the most stars joins the server's gacha pool as a hero. A week nobody's
    challenger won a fight in has none (`character_id` null)."""

    __tablename__ = "weekly_hero"
    __table_args__ = (UniqueConstraint("server_id", "day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    server_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server.id", ondelete="CASCADE"), nullable=False
    )
    # The finale day of the week.
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    character_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), unique=True
    )
    # Its stars in the end: the challenger's with its boosts, and its votes.
    stars: Mapped[int | None] = mapped_column(Integer)
    votes: Mapped[int | None] = mapped_column(Integer)
    decided_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    character: Mapped[Character | None] = relationship()
