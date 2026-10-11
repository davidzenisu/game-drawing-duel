"""theme hints and premade titles

Revision ID: d1ff7e7a9291
Revises: 9e12c3950a88
Create Date: 2026-10-11 10:12:16.983997

"""
import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

import sqlalchemy as sa

from alembic import op

# The first hints and titles (docs/concept/themes.md). Dated well before any
# game day, so they count from the first day on; rows added later count from
# the day after they were added.
SEEDED_AT = datetime(2026, 1, 1, tzinfo=UTC)

HINTS = {
    "forest": (
        'a challenger lost on the way to work',
        'a challenger who walks the dog at dawn',
        'a challenger waiting at a bus stop in the rain',
        'a challenger hiding from Monday morning',
        'a challenger jogging laps in the park',
        'a challenger building a flat-pack wardrobe',
        "a challenger who forages at the farmers' market",
        'a challenger who takes the scenic route to school',
    ),
    "beach": (
        'a challenger soaking up their lunch break sun',
        'a challenger who reserves the sunbeds at dawn',
        'a challenger doing laps at the public pool',
        "a challenger planning a holiday they'll never take",
        'a challenger building castles in the playground sandbox',
        'a challenger chasing the ice cream van',
        'a challenger relaxing in a bubble bath',
        'a challenger who forgot the sunscreen',
    ),
    "volcano": (
        'a challenger who can take the heat in the sauna',
        'a challenger who burns dinner every night',
        'a challenger whose laptop is overheating',
        'a challenger who orders the spiciest dish',
        'a challenger about to lose their temper in a meeting',
        'a challenger guarding the office radiator',
        'a challenger who drinks their coffee scalding hot',
        'a challenger in charge of the barbecue',
    ),
    "snow": (
        "a challenger who can't decide on an ice cream flavour",
        'a challenger scraping ice off the windshield',
        'a challenger who keeps the air conditioning on full',
        'a challenger braving a cold shower',
        'a challenger who forgot the frozen pizza in the oven',
        'a challenger defrosting the freezer',
        'a challenger who wears shorts in winter',
        'a challenger guarding the office thermostat',
    ),
    "jungle": (
        'a challenger lost in the fog machine on a night out',
        'a challenger whose houseplants have taken over',
        "a challenger who hasn't mowed the lawn in months",
        'a challenger in a steamy bathroom after a long shower',
        'a challenger untangling the cables behind the TV',
        'a challenger fighting through the Friday rush hour',
        'a challenger at a muddy music festival',
        'a challenger conquering the indoor playground',
    ),
    "space": (
        'a challenger orbiting the spin cycle at the laundromat',
        'a challenger lost in a furniture store maze',
        'a challenger battling the self-checkout',
        'a challenger running nowhere on a treadmill',
        'a challenger stuck in a waiting room for hours',
        'a challenger who stays up all night gaming',
        'a challenger hunting for a parking space at the mall',
        'a challenger stargazing from the rooftop',
    ),
    "castle": (
        'a challenger who rules from the couch',
        'a challenger hosting Sunday lunch',
        'a challenger who never loses at board games',
        'a challenger building a fort out of blankets',
        'a challenger who expects breakfast in bed',
        'a challenger defending the last slice of cake',
        'a challenger who refuses to tidy their room',
        'a challenger guarding the TV remote',
    ),
}

TITLES = {
    "forest": (
        'Keeper of the Last Bus Seat',
        'Druid of the Delayed 7:42',
        'The One Who Stands on the Left',
        'Whisperer of Ticket Machines',
        'Ranger of the Dog Park',
        'Hermit of the Bus Shelter',
        'Lord of the Flat-Pack Wardrobe',
        'Oracle of the Weather App',
        'Moss-Covered Monday Survivor',
        'Guardian of the Bike Rack',
        'Elder of the Allotment',
        'Squirrel-Feeding Sage',
    ),
    "beach": (
        'Sunbather of the Office Lawn',
        'Guardian of the Last Sandwich',
        'Microwave Queue Champion',
        'The Desk-Lunch Castaway',
        'Towel Warlord of Sunbed Row',
        'Lifeguard of the Kiddie Pool',
        'Captain of the Rubber Duck',
        'Ice Cream Van Pursuer',
        'The Flip-Flop Philosopher',
        'Sunscreen Skeptic',
        'Ruler of the Balcony Deckchair',
        'Sandbox Architect',
    ),
    "volcano": (
        'Lord of the Top Sauna Bench',
        'Ladle-Wielder of the Infusion',
        'The Towel That Never Slipped',
        'Grill Master of the Burnt Sausage',
        'Fire-Breather of the Hot Sauce',
        'Keeper of the Overheating Laptop',
        'Smoke Alarm Summoner',
        'Midweek Meltdown Monarch',
        'Radiator Hugger Supreme',
        'Espresso Eruption',
        'The Toast Incinerator',
        'Baron of the Hot Tub',
    ),
    "snow": (
        'Yeti of Aisle 7',
        'Frost Baron of the Frozen Peas',
        'Pizza-Box Mountaineer',
        'The One Who Holds the Freezer Door Open',
        'Windshield Scraper Knight',
        'Ice Cube Hoarder',
        'Thermostat Tyrant',
        'The Shorts-in-January Legend',
        'Snowplough of the Office Kitchen',
        "Keeper of Last Year's Leftovers",
        'Brain-Freeze Champion',
        'Duke of the Defrosted Fridge',
    ),
    "jungle": (
        'Dancer in the Dry-Ice Mist',
        'Chieftain of the Coat Check',
        'Explorer of the Sticky Floor',
        'The Last One at the Kebab Shop',
        'Monstera Whisperer',
        'Lord of the Unmowed Lawn',
        'Cable Tangle Tamer',
        'Sage of the Steamed-Up Mirror',
        'Festival Mud Wrestler',
        'Ball Pit Survivor',
        'Vine-Swinging Commuter',
        'Keeper of the Office Fern',
    ),
    "space": (
        'Commander of Machine No. 4',
        'Astronaut of the Endless Spin',
        'Finder of the Lost Socks',
        'The Fabric Softener Alien',
        'Navigator of the Showroom Maze',
        'Unexpected Item in the Bagging Area',
        'Treadmill Cosmonaut',
        'Waiting Room Time Traveller',
        'Parking Lot Satellite',
        'Midnight Console Pilot',
        'Explorer of the Meatball Station',
        'The Shopping Trolley Rover',
    ),
    "castle": (
        'Sovereign of the Remote',
        'Duke of the Duvet Fort',
        'Keeper of the Breakfast Crumbs',
        'Monarch of the Sweatpants',
        'Lord of the Sunday Roast',
        'Board Game Tyrant',
        'Defender of the Last Cake Slice',
        'Knight of the Messy Bedroom',
        'Baron of the Brunch Table',
        'The Nap Emperor',
        "Grandma's Favourite Heir",
        'Jester of the Family Group Chat',
    ),
}

# revision identifiers, used by Alembic.
revision: str = 'd1ff7e7a9291'
down_revision: str | Sequence[str] | None = '9e12c3950a88'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    # ### commands auto generated by Alembic - please adjust! ###
    op.create_table('premade_title',
    sa.Column('id', sa.Uuid(), server_default=sa.text('gen_random_uuid()'), nullable=False),
    sa.Column('theme', sa.String(length=20), nullable=False),
    sa.Column('title', sa.String(length=60), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_premade_title_theme'), 'premade_title', ['theme'], unique=False)
    op.create_table('theme_hint',
    sa.Column('id', sa.Uuid(), server_default=sa.text('gen_random_uuid()'), nullable=False),
    sa.Column('theme', sa.String(length=20), nullable=False),
    sa.Column('text', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_theme_hint_theme'), 'theme_hint', ['theme'], unique=False)
    # ### end Alembic commands ###
    hint_table = sa.table(
        "theme_hint",
        sa.column("id", sa.Uuid()),
        sa.column("theme", sa.String()),
        sa.column("text", sa.Text()),
        sa.column("created_at", sa.DateTime(timezone=True)),
    )
    op.bulk_insert(
        hint_table,
        [
            {"id": uuid.uuid4(), "theme": theme, "text": text, "created_at": SEEDED_AT}
            for theme, texts in HINTS.items()
            for text in texts
        ],
    )
    title_table = sa.table(
        "premade_title",
        sa.column("id", sa.Uuid()),
        sa.column("theme", sa.String()),
        sa.column("title", sa.String()),
        sa.column("created_at", sa.DateTime(timezone=True)),
    )
    op.bulk_insert(
        title_table,
        [
            {"id": uuid.uuid4(), "theme": theme, "title": title, "created_at": SEEDED_AT}
            for theme, titles in TITLES.items()
            for title in titles
        ],
    )


def downgrade() -> None:
    """Downgrade schema."""
    # ### commands auto generated by Alembic - please adjust! ###
    op.drop_index(op.f('ix_theme_hint_theme'), table_name='theme_hint')
    op.drop_table('theme_hint')
    op.drop_index(op.f('ix_premade_title_theme'), table_name='premade_title')
    op.drop_table('premade_title')
    # ### end Alembic commands ###
