"""retire test sessions

Speed mode replaces the test sessions: the ones still running are closed
for their players, as if cancelled, until `POST /admin/servers/cleanup`
deletes them. Their game data stays until then.

Revision ID: b17ad0eded77
Revises: 2ac4c09ade66
Create Date: 2026-10-31 10:21:37.402115

"""
from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'b17ad0eded77'
down_revision: str | Sequence[str] | None = '2ac4c09ade66'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute(
        'update game.server set cancelled_at = now() '
        'where is_test and cancelled_at is null'
    )


def downgrade() -> None:
    """Downgrade schema."""
    # The closed test sessions stay closed: they can't be told apart from the
    # ones their players cancelled.
