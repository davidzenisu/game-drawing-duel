"""suggestions

Ideas and bug reports players post on their server's feedback board, and
their upvotes.

Revision ID: c3a7e5d1f204
Revises: 9fba82d4e2b2
Create Date: 2026-11-13 11:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'c3a7e5d1f204'
down_revision: str | Sequence[str] | None = '9fba82d4e2b2'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('suggestion',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('server_id', sa.Uuid(), nullable=False),
    sa.Column('author_seat_id', sa.Uuid(), nullable=False),
    sa.Column('kind', sa.String(length=10), nullable=False),
    sa.Column('title', sa.String(length=80), nullable=False),
    sa.Column('description', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['author_seat_id'], ['game.server_seat.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['server_id'], ['game.server.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    schema='game'
    )
    op.create_index(op.f('ix_suggestion_server_id'), 'suggestion', ['server_id'], unique=False, schema='game')
    op.create_table('suggestion_vote',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('suggestion_id', sa.Uuid(), nullable=False),
    sa.Column('seat_id', sa.Uuid(), nullable=False),
    sa.Column('voted_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['seat_id'], ['game.server_seat.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['suggestion_id'], ['game.suggestion.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('suggestion_id', 'seat_id'),
    schema='game'
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('suggestion_vote', schema='game')
    op.drop_index(op.f('ix_suggestion_server_id'), table_name='suggestion', schema='game')
    op.drop_table('suggestion', schema='game')
