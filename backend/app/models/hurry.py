import uuid
from datetime import datetime

from sqlalchemy import (
    DateTime,
    Float,
    ForeignKey,
    Integer,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, utc_now


class Hurry(Base):
    """A seat's free daily hurry: it cuts another seat's challenger drawing
    time the day after it was sent (`day`), as a surprise while drawing."""

    __tablename__ = "hurry"
    __table_args__ = (UniqueConstraint("sender_seat_id", "day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    sender_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    target_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    # The day it hits: the day after it was sent. One a sender and day.
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    # A random share in [0, 1) that places it within its stretch of the
    # day's hurries (`rules.hurry_hits`). Named for when it was the share of
    # the time limit it hit at.
    at_fraction: Mapped[float] = mapped_column(Float, nullable=False)
    sent_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )
