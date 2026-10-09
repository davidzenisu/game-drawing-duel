import os
from typing import Annotated

from fastapi import Depends, FastAPI, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.auth import get_auth0_subject
from app.database import get_db
from app.routers import characters, me, servers, setup

app = FastAPI(title="Game Drawing Duel API", version="0.1.0")


def configure_frontend_cors(application: FastAPI) -> None:
    frontend_url = os.getenv("FRONTEND_URL")
    if frontend_url:
        application.add_middleware(
            CORSMiddleware,
            allow_origins=[frontend_url],
            allow_methods=["*"],
            allow_headers=["*"],
        )


configure_frontend_cors(app)


@app.get("/health", tags=["health"])
def health_check(
    session: Annotated[Session, Depends(get_db)],
) -> JSONResponse:
    """Public: reports whether the API can reach its database."""
    try:
        session.execute(text("SELECT 1"))
    except SQLAlchemyError:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "error", "database": "unavailable"},
        )
    return JSONResponse(content={"status": "ok", "database": "ok"})


# Everything except the health check and the API docs requires a signed-in user.
_authenticated = [Depends(get_auth0_subject)]
app.include_router(me.router, dependencies=_authenticated)
app.include_router(servers.router, dependencies=_authenticated)
app.include_router(setup.router, dependencies=_authenticated)
app.include_router(characters.router, dependencies=_authenticated)
