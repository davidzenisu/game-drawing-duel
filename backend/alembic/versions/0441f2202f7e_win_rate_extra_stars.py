"""win rate extra stars

The extra stars a fight's challenger and each of its fighters got from
their players' win rates of the week before. Earlier fights had none.

Revision ID: 0441f2202f7e
Revises: 23e90dff60ad
Create Date: 2026-11-02 20:10:21.242900

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0441f2202f7e"
down_revision: str | Sequence[str] | None = "23e90dff60ad"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "fight",
        sa.Column(
            "challenger_extra_stars", sa.Integer(), server_default="0", nullable=False
        ),
        schema="game",
    )
    op.add_column(
        "fighter",
        sa.Column("extra_stars", sa.Integer(), server_default="0", nullable=False),
        schema="game",
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("fighter", "extra_stars", schema="game")
    op.drop_column("fight", "challenger_extra_stars", schema="game")
