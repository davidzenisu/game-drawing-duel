"""gift stars

Gifts give stars too, besides pulls; with neither, they're just a message.

Revision ID: e5b2a7c41d90
Revises: d81f0c2a9e35
Create Date: 2026-11-13 19:40:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'e5b2a7c41d90'
down_revision: str | Sequence[str] | None = 'd81f0c2a9e35'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('gift', sa.Column('stars', sa.Integer(), server_default='0', nullable=False), schema='game')


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('gift', 'stars', schema='game')
