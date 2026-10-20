"""game schema

Moves the game's tables out of `public`, which Supabase's Data API serves,
into their own schema. The version table moves along in `env.py`, before
Alembic reads it, and stays there on a downgrade.

Revision ID: 1444e02ae228
Revises: 3be984f7bd0e
Create Date: 2026-10-20 06:30:00.000000

"""
from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '1444e02ae228'
down_revision: str | Sequence[str] | None = '3be984f7bd0e'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

SCHEMA = 'game'

# Every table at this revision. Indexes, constraints and foreign keys move
# along with them.
TABLES = (
    'boost',
    'challenger_prompt',
    'character',
    'day_end',
    'fight',
    'fighter',
    'finale_vote',
    'hint_assignment',
    'hurry',
    'player',
    'pull',
    'pull_grant',
    'server',
    'server_seat',
    'setup_assignment',
    'theme_hint',
    'tutorial_seen',
    'upgrade',
    'weekly_hero',
)


def upgrade() -> None:
    """Upgrade schema."""
    op.execute(f'CREATE SCHEMA IF NOT EXISTS {SCHEMA}')
    for table in TABLES:
        op.execute(f'ALTER TABLE public.{table} SET SCHEMA {SCHEMA}')


def downgrade() -> None:
    """Downgrade schema."""
    for table in TABLES:
        op.execute(f'ALTER TABLE {SCHEMA}.{table} SET SCHEMA public')
