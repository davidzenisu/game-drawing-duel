import uuid
from datetime import datetime

from sqlalchemy import (
    DateTime,
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


class WeeklyHero(Base):
    """A week's finale, decided once the week is over: the challenger with
    the most stars joins the server's gacha pool as a hero (`app.finale`). A
    week without challengers has none (`character_id` null)."""

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
    # Its stars: its own and its boost stars.
    stars: Mapped[int | None] = mapped_column(Integer)
    decided_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    character: Mapped[Character | None] = relationship()


class Trophy(Base):
    """A player stat's first place in a week (`app.player_stats`), won once
    the week is over; tied first places each have one. It came with
    `rules.STARS_FOR_WEEK_STAT` stars as a gift."""

    __tablename__ = "trophy"
    __table_args__ = (UniqueConstraint("seat_id", "stat", "day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # An `app.player_stats.STATS` key.
    stat: Mapped[str] = mapped_column(String(20), nullable=False)
    # The finale day of the week.
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    won_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )
