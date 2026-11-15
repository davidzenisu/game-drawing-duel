import os
from collections.abc import Generator
from datetime import UTC, datetime
from functools import lru_cache

from fastapi import HTTPException
from sqlalchemy import MetaData, create_engine
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

SCHEMA = "game"
"""The PostgreSQL schema of the game's tables. Supabase's Data API serves
`public`, so they're kept out of it, and apart from Supabase's own schemas."""


class Base(DeclarativeBase):
    # Index names leave out the schema, like they did before it.
    metadata = MetaData(schema=SCHEMA, naming_convention={"ix": "ix_%(table_name)s_%(column_0_name)s"})


def utc_now() -> datetime:
    """Creation times set by the API: precise to the microsecond, so rows
    created right after one another (even on SQLite) sort in order."""
    return datetime.now(UTC)


def engine_options(url: URL) -> dict:
    """How the API connects to its database.

    PostgreSQL goes through Supabase's transaction pooler (port 6543), which
    hands every transaction to any of its server connections: those don't
    share the statements psycopg prepares after a few runs of a query, so
    preparing is off. The pooler itself is cheap to connect to, so each API
    instance keeps a bigger pool than SQLAlchemy's default 5 + 10, and a
    request waiting for a free connection gives up after a few seconds
    rather than 30 (`DATABASE_POOL_SIZE`, `DATABASE_MAX_OVERFLOW` and
    `DATABASE_POOL_TIMEOUT` change those)."""
    if not url.drivername.startswith("postgresql"):
        return {"pool_pre_ping": True}
    return {
        "pool_pre_ping": True,
        "pool_size": int(os.getenv("DATABASE_POOL_SIZE", "10")),
        "max_overflow": int(os.getenv("DATABASE_MAX_OVERFLOW", "20")),
        "pool_timeout": float(os.getenv("DATABASE_POOL_TIMEOUT", "10")),
        # The pooler closes idle client connections after a while.
        "pool_recycle": 300,
        "connect_args": {"prepare_threshold": None},
    }


@lru_cache
def _get_session_factory(database_url: str) -> sessionmaker[Session]:
    url = make_url(database_url)
    if url.drivername in {"postgres", "postgresql"}:
        url = url.set(drivername="postgresql+psycopg")

    engine = create_engine(url, **engine_options(url))
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Generator[Session]:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise HTTPException(
            status_code=503,
            detail="The DATABASE_URL environment variable is not configured",
        )

    session_factory = _get_session_factory(database_url)
    with session_factory() as session:
        yield session
