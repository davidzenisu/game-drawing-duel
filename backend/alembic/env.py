import os
from logging.config import fileConfig

from sqlalchemy import Connection, engine_from_config, inspect, pool, text
from sqlalchemy.engine import make_url

import app.models  # noqa: F401  (registers every model on Base.metadata)
from alembic import context
from app.database import SCHEMA, Base

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

database_url = os.getenv("DATABASE_URL")
if not database_url:
    raise RuntimeError("DATABASE_URL must be set to run Alembic migrations")

url = make_url(database_url)
if url.drivername in {"postgres", "postgresql"}:
    url = url.set(drivername="postgresql+psycopg")
config.set_main_option(
    "sqlalchemy.url", url.render_as_string(hide_password=False).replace("%", "%%")
)

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

# other values from the config, defined by the needs of env.py,
# can be acquired:
# my_important_option = config.get_main_option("my_important_option")
# ... etc.


def include_name(name: str | None, type_: str, parent_names: object) -> bool:
    """Compares only the game's schema, not Supabase's or `public`."""
    if type_ == "schema":
        return name == SCHEMA
    return True


def use_game_schema(connection: Connection) -> None:
    """Runs the migrations in the game's schema, so the tables they create
    without naming one land there too. A fresh database gets the schema."""
    if not inspect(connection).has_schema(SCHEMA):
        connection.execute(text(f"CREATE SCHEMA {SCHEMA}"))
    connection.execute(text(f"SET search_path TO {SCHEMA}"))
    connection.commit()


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode.

    This configures the context with just a URL
    and not an Engine, though an Engine is acceptable
    here as well.  By skipping the Engine creation
    we don't even need a DBAPI to be available.

    Calls to context.execute() here emit the given string to the
    script output.

    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode.

    In this scenario we need to create an Engine
    and associate a connection with the context.

    """
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        use_game_schema(connection)
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            version_table_schema=SCHEMA,
            include_schemas=True,
            include_name=include_name,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
