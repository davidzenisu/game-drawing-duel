"""speed mode

A server's mode, "regular" or "speed", and the speed mode clock: the latest
day that started early and when.

Revision ID: 23e90dff60ad
Revises: b17ad0eded77
Create Date: 2026-10-31 13:52:11.904102

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '23e90dff60ad'
down_revision: str | Sequence[str] | None = 'b17ad0eded77'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('server', sa.Column('mode', sa.String(length=10), server_default='regular', nullable=False), schema='game')
    op.add_column('server', sa.Column('speed_day', sa.Integer(), nullable=True), schema='game')
    op.add_column('server', sa.Column('speed_day_started_at', sa.DateTime(timezone=True), nullable=True), schema='game')


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('server', 'speed_day_started_at', schema='game')
    op.drop_column('server', 'speed_day', schema='game')
    op.drop_column('server', 'mode', schema='game')
