import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.server import ServerSeat


class SetupAssignment(Base):
    """A drawing a seat has to make during the initial setup."""

    __tablename__ = "setup_assignment"
    __table_args__ = (UniqueConstraint("artist_seat_id", "prompt"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    artist_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    subject_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    # An `app.rules.SetupPrompt`.
    prompt: Mapped[str] = mapped_column(String(20), nullable=False)
    # The assignment this one builds on (the alter is based on the basic).
    based_on_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("setup_assignment.id", ondelete="CASCADE")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    artist: Mapped[ServerSeat] = relationship(foreign_keys=[artist_seat_id])
    subject: Mapped[ServerSeat] = relationship(foreign_keys=[subject_seat_id])
    based_on: Mapped["SetupAssignment | None"] = relationship(remote_side=[id])
