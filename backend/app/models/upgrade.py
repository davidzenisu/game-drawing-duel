import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, utc_now


class Upgrade(Base):
    """An effect a seat unlocked on one of its characters, paid with a
    duplicate."""

    __tablename__ = "upgrade"
    __table_args__ = (UniqueConstraint("seat_id", "character_id", "effect"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    character_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False
    )
    # An `app.rules.UpgradeEffect`.
    effect: Mapped[str] = mapped_column(String(20), nullable=False)
    # The `app.rules.Element` chosen for the element upgrade.
    element: Mapped[str | None] = mapped_column(String(20))
    unlocked_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )
