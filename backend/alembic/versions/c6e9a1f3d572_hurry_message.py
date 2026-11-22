"""hurry message

A short message the sender can add to a hurry.

Revision ID: c6e9a1f3d572
Revises: b4e8f2a6c913
Create Date: 2026-11-21 10:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'c6e9a1f3d572'
down_revision: str | Sequence[str] | None = 'b4e8f2a6c913'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'hurry',
        sa.Column('message', sa.String(length=60), nullable=True),
        schema='game',
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('hurry', 'message', schema='game')
