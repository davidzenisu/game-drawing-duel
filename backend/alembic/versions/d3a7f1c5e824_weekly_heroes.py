"""weekly heroes

A week's finale crowns its top 3 as weekly heroes, each with its place and
the rarity it was crowned with. Past finales crowned one hero, 3 star, in
1st place.

Revision ID: d3a7f1c5e824
Revises: c6e9a1f3d572
Create Date: 2026-11-22 10:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "d3a7f1c5e824"
down_revision: str | Sequence[str] | None = "c6e9a1f3d572"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "weekly_hero", sa.Column("place", sa.Integer(), nullable=True), schema="game"
    )
    op.add_column(
        "weekly_hero",
        sa.Column("rarity", sa.String(length=20), nullable=True),
        schema="game",
    )
    op.execute(
        "update game.weekly_hero set place = 1, rarity = 'hero' where character_id is not null"
    )
    op.drop_constraint("weekly_hero_server_id_day_key", "weekly_hero", schema="game")
    op.create_unique_constraint(
        "weekly_hero_server_id_day_character_id_key",
        "weekly_hero",
        ["server_id", "day", "character_id"],
        schema="game",
        postgresql_nulls_not_distinct=True,
    )


def downgrade() -> None:
    """Downgrade schema."""
    # Keeps the 1st place of each finale, as a 3 star: every challenger is
    # drawn as one.
    op.execute("delete from game.weekly_hero where place > 1")
    op.execute("update game.character set rarity = 'hero' where assignment_id is null")
    op.drop_constraint(
        "weekly_hero_server_id_day_character_id_key", "weekly_hero", schema="game"
    )
    op.create_unique_constraint(
        "weekly_hero_server_id_day_key",
        "weekly_hero",
        ["server_id", "day"],
        schema="game",
    )
    op.drop_column("weekly_hero", "rarity", schema="game")
    op.drop_column("weekly_hero", "place", schema="game")
