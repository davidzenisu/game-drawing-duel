import os
from collections.abc import Generator
from datetime import UTC, datetime
from functools import lru_cache

from fastapi import HTTPException
from sqlalchemy import MetaData, create_engine
from sqlalchemy.engine import make_url
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


@lru_cache
def _get_session_factory(database_url: str) -> sessionmaker[Session]:
    url = make_url(database_url)
    if url.drivername in {"postgres", "postgresql"}:
        url = url.set(drivername="postgresql+psycopg")

    engine = create_engine(url, pool_pre_ping=True)
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
