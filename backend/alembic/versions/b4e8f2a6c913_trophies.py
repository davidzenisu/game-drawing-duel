"""trophies

The first places of each player stat in a week, won once it's over.

Revision ID: b4e8f2a6c913
Revises: a9d4e6b8c312
Create Date: 2026-11-17 18:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'b4e8f2a6c913'
down_revision: str | Sequence[str] | None = 'a9d4e6b8c312'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('trophy',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('seat_id', sa.Uuid(), nullable=False),
    sa.Column('stat', sa.String(length=20), nullable=False),
    sa.Column('day', sa.Integer(), nullable=False),
    sa.Column('won_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['seat_id'], ['game.server_seat.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('seat_id', 'stat', 'day'),
    schema='game'
    )
    op.create_index(op.f('ix_trophy_seat_id'), 'trophy', ['seat_id'], unique=False, schema='game')


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_trophy_seat_id'), table_name='trophy', schema='game')
    op.drop_table('trophy', schema='game')
