import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
    false,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, utc_now
from app.models.character import Character


class Fight(Base):
    """Step 3 of the daily loop: up to four fighters a seat sent against a
    challenger drawn the day before. The others may boost the challenger the
    next day; the day after, the stars decide."""

    __tablename__ = "fight"
    __table_args__ = (UniqueConstraint("owner_seat_id", "day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    owner_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    # The day the fighters were picked.
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    challenger_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False
    )
    # The owner picked nobody, so the fighters were picked by chance.
    by_chance: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=false()
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    challenger: Mapped[Character] = relationship()
    fighters: Mapped[list["Fighter"]] = relationship(
        order_by="Fighter.position", cascade="all, delete-orphan"
    )


class Fighter(Base):
    """A character sent into a fight, with the upgrades it had then."""

    __tablename__ = "fighter"
    __table_args__ = (
        UniqueConstraint("fight_id", "position"),
        UniqueConstraint("fight_id", "character_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    fight_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("fight.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    character_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False
    )
    # Comma-separated `app.rules.UpgradeEffect`s, in path order.
    upgrades: Mapped[str] = mapped_column(String(100), nullable=False, default="")
    # An `app.rules.Element`.
    element: Mapped[str | None] = mapped_column(String(20))

    character: Mapped[Character] = relationship()


class Boost(Base):
    """Step 4: a seat's daily boost for one of the day before's challengers.
    Each boost adds more stars than the one before, see `rules.boost_stars`."""

    __tablename__ = "boost"
    __table_args__ = (UniqueConstraint("booster_seat_id", "day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    booster_seat_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("server_seat.id", ondelete="CASCADE"), nullable=False
    )
    challenger_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("character.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # The day of the boost, the day after the challenger's fights.
    day: Mapped[int] = mapped_column(Integer, nullable=False)
    boosted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )
