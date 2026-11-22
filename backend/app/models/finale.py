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
    """A weekly hero, crowned by its week's finale once the week is over:
    up to `rules.FINALE_MAX_HEROES` of the week's challengers join the
    server's gacha pool, each with a rarity by its stars (`app.finale`).
    A week without any has one row without a character (`character_id`
    null), so it counts as decided."""

    __tablename__ = "weekly_hero"
    __table_args__ = (
        # Challengers tied for 1st share their place; one row without a
        # character for a week without heroes.
        UniqueConstraint(
            "server_id", "day", "character_id", postgresql_nulls_not_distinct=True
        ),
    )

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
    # Its place in the week's ranking, 1 to 3; heroes tied for 1st share it.
    place: Mapped[int | None] = mapped_column(Integer)
    # The `app.rules.Rarity` it was crowned with, now the character's.
    rarity: Mapped[str | None] = mapped_column(String(20))
    # The starter legend featured with the finale's heroes on the weekly
    # banner (`app.pulls.rate_up`): one portraying a 1st place's player, when
    # no hero is a legend. The same on every hero of the finale.
    legend_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("character.id", ondelete="SET NULL")
    )
    decided_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        server_default=func.now(),
    )

    character: Mapped[Character | None] = relationship(foreign_keys=[character_id])


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
