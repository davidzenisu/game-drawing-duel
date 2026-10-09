"""uuid primary keys

Recreates the game tables with UUID primary keys; their data is dropped.

Revision ID: 024ae4505be8
Revises: 6e0cc718a467
Create Date: 2026-10-09 21:07:16.943061

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '024ae4505be8'
down_revision: str | Sequence[str] | None = '6e0cc718a467'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# Every game table, children first.
_TABLES = ("character", "setup_assignment", "server_seat", "server", "player")


def upgrade() -> None:
    """Drop the game tables and their data; recreate them with UUID keys."""
    # Children first: each table is referenced by the ones dropped before it.
    for table in _TABLES:
        op.drop_table(table)
    op.create_table('player',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('auth0_id', sa.String(length=255), nullable=False),
    sa.Column('first_name', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('auth0_id')
    )
    op.create_table('server',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('code', sa.String(length=6), nullable=False),
    sa.Column('admin_id', sa.Uuid(), nullable=False),
    sa.Column('is_test', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('setup_started_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('launched_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['admin_id'], ['player.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('code')
    )
    op.create_table('server_seat',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('server_id', sa.Uuid(), nullable=False),
    sa.Column('position', sa.Integer(), nullable=False),
    sa.Column('name', sa.Text(), nullable=False),
    sa.Column('player_id', sa.Uuid(), nullable=True),
    sa.Column('joined_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('setup_done_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['player_id'], ['player.id'], ),
    sa.ForeignKeyConstraint(['server_id'], ['server.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('server_id', 'player_id'),
    sa.UniqueConstraint('server_id', 'position')
    )
    op.create_table('setup_assignment',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('artist_seat_id', sa.Uuid(), nullable=False),
    sa.Column('subject_seat_id', sa.Uuid(), nullable=False),
    sa.Column('prompt', sa.String(length=20), nullable=False),
    sa.Column('based_on_id', sa.Uuid(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['artist_seat_id'], ['server_seat.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['based_on_id'], ['setup_assignment.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['subject_seat_id'], ['server_seat.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('artist_seat_id', 'prompt')
    )
    op.create_table('character',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('server_id', sa.Uuid(), nullable=False),
    sa.Column('artist_seat_id', sa.Uuid(), nullable=False),
    sa.Column('subject_seat_id', sa.Uuid(), nullable=False),
    sa.Column('assignment_id', sa.Uuid(), nullable=True),
    sa.Column('title', sa.Text(), nullable=False),
    sa.Column('rarity', sa.String(length=20), nullable=False),
    sa.Column('prompt', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['artist_seat_id'], ['server_seat.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['assignment_id'], ['setup_assignment.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['server_id'], ['server.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['subject_seat_id'], ['server_seat.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('assignment_id')
    )


def downgrade() -> None:
    """Back to integer keys; the data is dropped again."""
    # Children first: each table is referenced by the ones dropped before it.
    for table in _TABLES:
        op.drop_table(table)
    op.create_table('player',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('auth0_id', sa.String(length=255), nullable=False),
    sa.Column('first_name', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('auth0_id')
    )
    op.create_table('server',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('code', sa.String(length=6), nullable=False),
    sa.Column('admin_id', sa.Integer(), nullable=False),
    sa.Column('is_test', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('setup_started_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('launched_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['admin_id'], ['player.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('code')
    )
    op.create_table('server_seat',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('server_id', sa.Integer(), nullable=False),
    sa.Column('position', sa.Integer(), nullable=False),
    sa.Column('name', sa.Text(), nullable=False),
    sa.Column('player_id', sa.Integer(), nullable=True),
    sa.Column('joined_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('setup_done_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['player_id'], ['player.id'], ),
    sa.ForeignKeyConstraint(['server_id'], ['server.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('server_id', 'player_id'),
    sa.UniqueConstraint('server_id', 'position')
    )
    op.create_table('setup_assignment',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('artist_seat_id', sa.Integer(), nullable=False),
    sa.Column('subject_seat_id', sa.Integer(), nullable=False),
    sa.Column('prompt', sa.String(length=20), nullable=False),
    sa.Column('based_on_id', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['artist_seat_id'], ['server_seat.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['based_on_id'], ['setup_assignment.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['subject_seat_id'], ['server_seat.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('artist_seat_id', 'prompt')
    )
    op.create_table('character',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('server_id', sa.Integer(), nullable=False),
    sa.Column('artist_seat_id', sa.Integer(), nullable=False),
    sa.Column('subject_seat_id', sa.Integer(), nullable=False),
    sa.Column('assignment_id', sa.Integer(), nullable=True),
    sa.Column('title', sa.Text(), nullable=False),
    sa.Column('rarity', sa.String(length=20), nullable=False),
    sa.Column('prompt', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['artist_seat_id'], ['server_seat.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['assignment_id'], ['setup_assignment.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['server_id'], ['server.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['subject_seat_id'], ['server_seat.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('assignment_id')
    )
