"""stars

Stars, the currency players collect: one grant per reward. The victory
stars of the fights players won so far carry over.

Revision ID: d81f0c2a9e35
Revises: c3a7e5d1f204
Create Date: 2026-11-13 16:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'd81f0c2a9e35'
down_revision: str | Sequence[str] | None = 'c3a7e5d1f204'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('star_grant',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('seat_id', sa.Uuid(), nullable=False),
    sa.Column('reason', sa.String(length=100), nullable=False),
    sa.Column('stars', sa.Integer(), nullable=False),
    sa.Column('granted_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['seat_id'], ['game.server_seat.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('seat_id', 'reason'),
    schema='game'
    )
    # The victory stars so far: the challenger's stars of every fight a
    # player picked the fighters for and won, as a won fight now earns.
    op.execute(
        """
        INSERT INTO game.star_grant (id, seat_id, reason, stars, granted_at)
        SELECT gen_random_uuid(), owner_seat_id, 'fight:day-' || day,
               challenger_stars, now()
        FROM game.fight
        WHERE fighters_win AND NOT by_chance AND challenger_stars IS NOT NULL
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('star_grant', schema='game')
