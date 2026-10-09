import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.server import ServerSeat
from app.models.setup import SetupAssignment


class Character(Base):
    """A drawn character of a server's pool.

    The drawing itself is a file in storage named after the character's id.
    """

    __tablename__ = "character"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    server_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server.id", ondelete="CASCADE"), nullable=False
    )
    artist_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    subject_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    # The setup drawing this character was drawn for; redrawing replaces it.
    assignment_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("setup_assignment.id", ondelete="CASCADE"), unique=True
    )
    title: Mapped[str] = mapped_column(Text, nullable=False)
    # An `app.rules.Rarity`.
    rarity: Mapped[str] = mapped_column(String(20), nullable=False)
    # An `app.rules.SetupPrompt` for setup drawings.
    prompt: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    artist: Mapped[ServerSeat] = relationship(foreign_keys=[artist_seat_id])
    subject: Mapped[ServerSeat] = relationship(foreign_keys=[subject_seat_id])
    assignment: Mapped[SetupAssignment | None] = relationship()
