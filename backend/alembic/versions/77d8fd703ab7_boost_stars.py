"""boost stars

Boosting moves before the fight: every day, a player spreads boost stars
across the day before's challengers, several a day, and chance spreads the
ones they leave. Earlier boosts count as one star each.

Revision ID: 77d8fd703ab7
Revises: a2d98967af7a
Create Date: 2026-10-31 10:12:08.512334

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '77d8fd703ab7'
down_revision: str | Sequence[str] | None = 'a2d98967af7a'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('boost', sa.Column('stars', sa.Integer(), server_default='1', nullable=False), schema='game')
    op.add_column('boost', sa.Column('by_chance', sa.Boolean(), server_default=sa.false(), nullable=False), schema='game')
    op.drop_constraint('boost_booster_seat_id_day_key', 'boost', schema='game', type_='unique')
    op.create_unique_constraint(
        'boost_booster_seat_id_day_challenger_id_by_chance_key',
        'boost',
        ['booster_seat_id', 'day', 'challenger_id', 'by_chance'],
        schema='game',
    )


def downgrade() -> None:
    """Downgrade schema."""
    # Keeps one boost per seat and day, as before.
    op.execute(
        """
        delete from game.boost b
        using game.boost other
        where b.booster_seat_id = other.booster_seat_id
          and b.day = other.day
          and (b.boosted_at, b.id) > (other.boosted_at, other.id)
        """
    )
    op.drop_constraint('boost_booster_seat_id_day_challenger_id_by_chance_key', 'boost', schema='game', type_='unique')
    op.create_unique_constraint('boost_booster_seat_id_day_key', 'boost', ['booster_seat_id', 'day'], schema='game')
    op.drop_column('boost', 'by_chance', schema='game')
    op.drop_column('boost', 'stars', schema='game')
