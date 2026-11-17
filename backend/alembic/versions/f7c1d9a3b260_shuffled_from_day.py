"""shuffled from day

Who draws whose prompt, and who boosts and fights whose challenger, are
handed round at random every day instead of in roster order. Games launched
from now on shuffle from day 1 (set at launch). Running games switch the day
after this goes live, so nothing a player has seen or started changes:
regular servers from tomorrow (UTC), test sessions from their next day.
Speed sessions running now keep the roster order to their end, a few days
away (null).

Revision ID: f7c1d9a3b260
Revises: e5b2a7c41d90
Create Date: 2026-11-17 09:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'f7c1d9a3b260'
down_revision: str | Sequence[str] | None = 'e5b2a7c41d90'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('server', sa.Column('shuffled_from_day', sa.Integer(), nullable=True), schema='game')
    # Day 1 is the launch day (UTC); tomorrow is today's day + 1.
    op.execute(
        """
        UPDATE game.server
        SET shuffled_from_day = (now() AT TIME ZONE 'UTC')::date
            - (launched_at AT TIME ZONE 'UTC')::date + 2
        WHERE launched_at IS NOT NULL AND NOT is_test AND mode = 'regular'
        """
    )
    op.execute(
        """
        UPDATE game.server
        SET shuffled_from_day = coalesce(test_day, 1) + 1
        WHERE launched_at IS NOT NULL AND is_test
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('server', 'shuffled_from_day', schema='game')
