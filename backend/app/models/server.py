from datetime import datetime

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Server(Base):
    """A group of friends playing together, joined with a 6-digit code."""

    __tablename__ = "server"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(6), nullable=False, unique=True)
    admin_id: Mapped[int] = mapped_column(ForeignKey("player.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    seats: Mapped[list["ServerSeat"]] = relationship(
        back_populates="server",
        order_by="ServerSeat.position",
        cascade="all, delete-orphan",
    )


class ServerSeat(Base):
    """A player name the admin prepopulated; claimed when that player joins."""

    __tablename__ = "server_seat"
    __table_args__ = (
        UniqueConstraint("server_id", "position"),
        UniqueConstraint("server_id", "player_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    server_id: Mapped[int] = mapped_column(
        ForeignKey("server.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    player_id: Mapped[int | None] = mapped_column(ForeignKey("player.id"))
    joined_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    server: Mapped[Server] = relationship(back_populates="seats")
