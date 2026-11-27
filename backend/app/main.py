import logging
import os
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import OperationalError, SQLAlchemyError
from sqlalchemy.exc import TimeoutError as SQLAlchemyTimeoutError
from sqlalchemy.orm import Session

from app.auth import get_auth0_subject
from app.database import get_db
from app.docs_login import configure_docs_login
from app.docs_page import configure_docs_page
from app.routers import (
    achievements,
    admin,
    arena,
    characters,
    content,
    gifts,
    me,
    player_stats,
    pool,
    servers,
    setup,
    suggestions,
    today,
)

# The docs page is served by `configure_docs_page`, with the game's logo.
app = FastAPI(title="Game Drawing Duel API", version="0.44.2", docs_url=None)

# The backend deployment writes the commit it deploys into this file; local
# runs and tests have none.
COMMIT_FILE = Path(__file__).resolve().parent / "commit.txt"


def running_commit() -> str:
    """The deployed commit hash, or "dev" when not deployed."""
    try:
        return COMMIT_FILE.read_text().strip() or "dev"
    except OSError:
        return "dev"


logger = logging.getLogger("app")


def configure_error_handling(application: FastAPI) -> None:
    """Logs every unhandled error with its request, and answers it as JSON:
    inside the CORS middleware, so the browser can still read the answer
    instead of reporting "Failed to fetch". An overloaded database (no free
    connection, or none to be had) is a 503: worth trying again."""

    @application.middleware("http")
    async def handle_errors(request: Request, call_next):
        try:
            return await call_next(request)
        except (SQLAlchemyTimeoutError, OperationalError):
            logger.exception("Database unavailable for %s %s", request.method, request.url.path)
            return JSONResponse(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                content={"detail": "The server is busy, try again in a moment"},
            )
        except Exception:
            logger.exception("Unhandled error in %s %s", request.method, request.url.path)
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={"detail": "Something went wrong on the server"},
            )


def configure_frontend_cors(application: FastAPI) -> None:
    frontend_url = os.getenv("FRONTEND_URL")
    if frontend_url:
        application.add_middleware(
            CORSMiddleware,
            allow_origins=[frontend_url],
            allow_methods=["*"],
            allow_headers=["*"],
        )


# Error handling first: middleware added later wraps it.
configure_error_handling(app)
configure_frontend_cors(app)


@app.get("/health", tags=["health"])
def health_check(
    session: Annotated[Session, Depends(get_db)],
) -> JSONResponse:
    """Public: reports whether the API can reach its database, and which
    commit is running (`version`)."""
    version = running_commit()
    try:
        session.execute(text("SELECT 1"))
    except SQLAlchemyError:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "error", "database": "unavailable", "version": version},
        )
    return JSONResponse(content={"status": "ok", "database": "ok", "version": version})


# Everything except the health check and the API docs (with their logo)
# requires a signed-in user.
_authenticated = [Depends(get_auth0_subject)]
app.include_router(me.router, dependencies=_authenticated)
app.include_router(servers.router, dependencies=_authenticated)
app.include_router(setup.router, dependencies=_authenticated)
app.include_router(characters.router, dependencies=_authenticated)
app.include_router(pool.router, dependencies=_authenticated)
app.include_router(today.router, dependencies=_authenticated)
app.include_router(arena.router, dependencies=_authenticated)
app.include_router(gifts.router, dependencies=_authenticated)
app.include_router(suggestions.router, dependencies=_authenticated)
app.include_router(achievements.router, dependencies=_authenticated)
app.include_router(player_stats.router, dependencies=_authenticated)
# Also needs the content permission.
app.include_router(content.router, dependencies=_authenticated)
app.include_router(admin.router, dependencies=_authenticated)

configure_docs_page(app)
configure_docs_login(app)
