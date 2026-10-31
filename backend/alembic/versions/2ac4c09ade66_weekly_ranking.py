"""weekly ranking

The finale no longer has votes: once a week is over, its challengers are
ranked by their stars and the first joins the pool as a hero. Drops the
votes and the hero's vote count; a downgrade starts without votes.

Revision ID: 2ac4c09ade66
Revises: 77d8fd703ab7
Create Date: 2026-10-31 09:02:41.118220

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '2ac4c09ade66'
down_revision: str | Sequence[str] | None = '77d8fd703ab7'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.drop_index(op.f('ix_finale_vote_chosen_id'), table_name='finale_vote', schema='game')
    op.drop_table('finale_vote', schema='game')
    op.drop_column('weekly_hero', 'votes', schema='game')


def downgrade() -> None:
    """Downgrade schema."""
    op.add_column('weekly_hero', sa.Column('votes', sa.Integer(), nullable=True), schema='game')
    op.execute('update game.weekly_hero set votes = 0 where character_id is not null')
    op.create_table('finale_vote',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('voter_seat_id', sa.Uuid(), nullable=False),
    sa.Column('day', sa.Integer(), nullable=False),
    sa.Column('first_id', sa.Uuid(), nullable=False),
    sa.Column('second_id', sa.Uuid(), nullable=False),
    sa.Column('chosen_id', sa.Uuid(), nullable=False),
    sa.Column('voted_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['chosen_id'], ['game.character.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['first_id'], ['game.character.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['second_id'], ['game.character.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['voter_seat_id'], ['game.server_seat.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('voter_seat_id', 'first_id', 'second_id'),
    schema='game'
    )
    op.create_index(op.f('ix_finale_vote_chosen_id'), 'finale_vote', ['chosen_id'], unique=False, schema='game')
