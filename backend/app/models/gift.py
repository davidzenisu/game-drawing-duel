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


class Gift(Base):
    """Pulls and stars an admin (`auth.ADMIN_PERMISSION`) gave players outside
    the regular rewards, with a message (neither, for just a message): to
    everyone on every server, to everyone on one server, or to chosen players
    of one. Each recipient's seat gets a `GiftDelivery` to accept."""

    __tablename__ = "gift"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    message: Mapped[str] = mapped_column(String(200), nullable=False)
    # The pulls and stars each recipient gets.
    pulls: Mapped[int] = mapped_column(Integer, nullable=False)
    stars: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    sender_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("player.id", ondelete="SET NULL")
    )
    # The server it went to; null when it went to every server.
    server_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("server.id", ondelete="CASCADE")
    )
    sent_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    deliveries: Mapped[list[GiftDelivery]] = relationship(
        back_populates="gift", cascade="all, delete-orphan"
    )


class GiftDelivery(Base):
    """A gift for one seat. Its pulls count once the player accepts it
    (`claimed_at`); gifts don't expire."""

    __tablename__ = "gift_delivery"
    __table_args__ = (UniqueConstraint("gift_id", "seat_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    gift_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("gift.id", ondelete="CASCADE"), nullable=False
    )
    seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False, index=True
    )
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    gift: Mapped[Gift] = relationship(back_populates="deliveries")
