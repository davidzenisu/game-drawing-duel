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


class PullGrant(Base):
    """One gacha pull awarded to a seat.

    `reason` names what earned it (e.g. "launch-bonus:3"), so the same reward
    can never be awarded twice.
    """

    __tablename__ = "pull_grant"
    __table_args__ = (UniqueConstraint("seat_id", "reason"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    reason: Mapped[str] = mapped_column(String(100), nullable=False)
    granted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )


class Pull(Base):
    """A gacha pull: spends exactly one grant on a character of the pool."""

    __tablename__ = "pull"
    __table_args__ = (UniqueConstraint("seat_id", "number"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    # Each grant pays for one pull only.
    grant_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("pull_grant.id", ondelete="CASCADE"), nullable=False, unique=True
    )
    character_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False
    )
    # The seat's pulls in order: 1, 2, 3, …
    number: Mapped[int] = mapped_column(Integer, nullable=False)
    # The rarity pulled, which the pity follows from. An `app.rules.Rarity`.
    rarity: Mapped[str] = mapped_column(String(20), nullable=False)
    pulled_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    character: Mapped[Character] = relationship()
