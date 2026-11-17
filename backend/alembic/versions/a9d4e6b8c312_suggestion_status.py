"""suggestion status

A status for every suggestion on the feedback board: open, in progress,
rejected or in review (set by server admins), and done once its author
confirmed it's fixed. Existing suggestions are open.

Revision ID: a9d4e6b8c312
Revises: f7c1d9a3b260
Create Date: 2026-11-17 12:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'a9d4e6b8c312'
down_revision: str | Sequence[str] | None = 'f7c1d9a3b260'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('suggestion', sa.Column('status', sa.String(length=12), server_default='open', nullable=False), schema='game')


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('suggestion', 'status', schema='game')
