"""premade titles on hints

Revision ID: 5e7b2c9d4f10
Revises: 8c2f1d0b7a51
Create Date: 2026-10-13 08:30:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '5e7b2c9d4f10'
down_revision: str | Sequence[str] | None = '8c2f1d0b7a51'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# The seeded hints (docs/concept/themes.md) with the premade title that comes
# with each, picked from the seeded titles of their theme (one is new). The
# other seeded titles go away with the premade_title table.
PAIRS = {
    "forest": (
        ('a challenger lost on the way to work', 'Druid of the Delayed 7:42'),
        ('a challenger who walks the dog at dawn', 'Ranger of the Dog Park'),
        ('a challenger waiting at a bus stop in the rain', 'Keeper of the Last Bus Seat'),
        ('a challenger hiding from Monday morning', 'Moss-Covered Monday Survivor'),
        ('a challenger jogging laps in the park', 'Squirrel-Feeding Sage'),
        ('a challenger cultivating their balcony garden', 'Elder of the Allotment'),
    ),
    "beach": (
        ('a challenger doing laps at the public pool', 'Lifeguard of the Kiddie Pool'),
        ('a challenger planning a holiday in spreadsheets', 'Towel Warlord of Sunbed Row'),
        ('a challenger building castles in the playground sandbox', 'Sandbox Architect'),
        ('a challenger fixing their broken down car on a road trip', 'Guardian of the Last Sandwich'),
        ('a challenger relaxing in a bubble bath', 'Captain of the Rubber Duck'),
        ('a challenger who forgot the sunscreen', 'Sunscreen Skeptic'),
    ),
    "volcano": (
        ('a challenger who can take the heat in the sauna', 'Lord of the Top Sauna Bench'),
        ('a challenger who burns dinner every night', 'Smoke Alarm Summoner'),
        ('a challenger whose laptop is overheating', 'Keeper of the Overheating Laptop'),
        ('a challenger who orders the spiciest dish', 'Fire-Breather of the Hot Sauce'),
        ('a challenger about to lose their temper in a meeting', 'Midweek Meltdown Monarch'),
        ('a challenger who drinks their coffee scalding hot', 'Espresso Eruption'),
        ('a challenger in charge of the barbecue', 'Grill Master of the Burnt Sausage'),
    ),
    "snow": (
        ("a challenger who can't decide on an ice cream flavour", 'Brain-Freeze Champion'),
        ('a challenger scraping ice off the windshield', 'Windshield Scraper Knight'),
        ('a challenger who keeps the air conditioning on full', 'Thermostat Tyrant'),
        ('a challenger braving a cold shower', 'Ice Cube Hoarder'),
        ('a challenger defrosting the freezer', 'Duke of the Defrosted Fridge'),
        ('a challenger who wears shorts in winter', 'The Shorts-in-January Legend'),
    ),
    "jungle": (
        ('a challenger who gets lost in the club', 'Explorer of the Sticky Floor'),
        ('a challenger ruling the dance floor', 'Dancer in the Dry-Ice Mist'),
        ('a challenger whose houseplants have taken over', 'Monstera Whisperer'),
        ('a challenger untangling the cables behind the TV', 'Cable Tangle Tamer'),
        ('a challenger fighting through the Friday rush hour jungle', 'Vine-Swinging Commuter'),
        ('a challenger at a muddy music festival', 'Festival Mud Wrestler'),
    ),
    "space": (
        ('a challenger lost in a furniture store maze', 'Navigator of the Showroom Maze'),
        ('a challenger fixing their washing machine', 'Astronaut of the Endless Spin'),
        ('a challenger stuck in a waiting room for hours', 'Waiting Room Time Traveller'),
        ('a challenger who stays up all night gaming', 'Midnight Console Pilot'),
        ('a challenger hunting for a parking space at the mall', 'Parking Lot Satellite'),
        ('a challenger stargazing from the rooftop', 'Captain of the Rooftop Telescope'),
    ),
    "castle": (
        ('a challenger who rules from the couch', 'The Nap Emperor'),
        ('a challenger hosting Sunday brunch', 'Baron of the Brunch Table'),
        ('a challenger building a fort out of blankets', 'Duke of the Duvet Fort'),
        ('a challenger who refuses to tidy their room', 'Knight of the Messy Bedroom'),
        ('a challenger guarding the TV remote', 'Sovereign of the Remote'),
        ('a challenger bad at losing board games', 'Board Game Tyrant'),
    ),
}

# For hints added by hand since, which had no title of their own.
FALLBACK_TITLE = 'The Mystery Challenger'


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('theme_hint', sa.Column('premade_title', sa.String(length=60), nullable=True))
    hint = sa.table(
        'theme_hint',
        sa.column('theme', sa.String),
        sa.column('text', sa.Text),
        sa.column('premade_title', sa.String),
    )
    for theme, pairs in PAIRS.items():
        for text, title in pairs:
            op.execute(
                hint.update()
                .where(hint.c.theme == theme, hint.c.text == text)
                .values(premade_title=title)
            )
    op.execute(hint.update().where(hint.c.premade_title.is_(None)).values(premade_title=FALLBACK_TITLE))
    op.alter_column('theme_hint', 'premade_title', nullable=False)
    op.drop_index(op.f('ix_premade_title_theme'), table_name='premade_title')
    op.drop_table('premade_title')


def downgrade() -> None:
    """Downgrade schema."""
    op.create_table('premade_title',
    sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), autoincrement=False, nullable=False),
    sa.Column('theme', sa.VARCHAR(length=20), autoincrement=False, nullable=False),
    sa.Column('title', sa.VARCHAR(length=60), autoincrement=False, nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), autoincrement=False, nullable=False),
    sa.Column('retired_at', sa.DateTime(timezone=True), autoincrement=False, nullable=True),
    sa.PrimaryKeyConstraint('id', name=op.f('premade_title_pkey'))
    )
    op.create_index(op.f('ix_premade_title_theme'), 'premade_title', ['theme'], unique=False)
    # Every hint's title becomes a premade title of its own again.
    op.execute(
        "INSERT INTO premade_title (id, theme, title, created_at, retired_at) "
        "SELECT gen_random_uuid(), theme, premade_title, created_at, retired_at FROM theme_hint "
        f"WHERE premade_title <> '{FALLBACK_TITLE}'"
    )
    op.drop_column('theme_hint', 'premade_title')


