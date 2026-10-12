import uuid
from datetime import datetime

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, utc_now
from app.models.theme import ThemeHint


class ChallengerPrompt(Base):
    """Step 1 of the daily loop: a challenger title a seat wrote for a day's
    theme and a character; the next seat draws it the day after."""

    __tablename__ = "challenger_prompt"
    __table_args__ = (UniqueConstraint("author_seat_id", "day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    author_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    subject_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    title: Mapped[str] = mapped_column(Text, nullable=False)
    # An `app.rules.Theme`.
    theme: Mapped[str] = mapped_column(String(20), nullable=False)
    # The description the author chose the person and wrote the title for,
    # if the theme had any.
    hint: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )


class DayEnd(Base):
    """A seat ended its day of a test session."""

    __tablename__ = "day_end"
    __table_args__ = (UniqueConstraint("seat_id", "day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    ended_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )


class HintAssignment(Base):
    """The prompt hint a seat got to write a challenger title for on a day.

    A server uses every hint once at most, ever: a seat gets none (`hint_id`
    null) once the server used up the theme's hints. Stored the first time
    anyone asks for the day's hints, for every seat at once."""

    __tablename__ = "hint_assignment"
    __table_args__ = (
        UniqueConstraint("seat_id", "day"),
        UniqueConstraint("server_id", "hint_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    server_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server.id", ondelete="CASCADE"), nullable=False
    )
    seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    hint_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("theme_hint.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    hint: Mapped[ThemeHint | None] = relationship()
