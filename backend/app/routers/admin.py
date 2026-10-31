"""Housekeeping for the accounts with the admin permission
(`auth.ADMIN_PERMISSION`)."""

from datetime import timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select

from app.auth import require_server_admin
from app.database import utc_now
from app.models import Server
from app.routers.servers import DbSession, delete_game_data
from app.schemas import CleanupResponse
from app.storage import Files, delete_quietly

router = APIRouter(
    prefix="/admin",
    tags=["admin"],
    dependencies=[Depends(require_server_admin)],
)

# Test sessions are deleted once they're this old.
SHORT_LIVED_FOR = timedelta(days=1)


@router.post("/servers/cleanup", response_model=CleanupResponse)
def clean_up_servers(session: DbSession, files: Files) -> CleanupResponse:
    """Deletes every test session created more than a day ago, with its
    seats, game data and drawings. Players can't open test sessions anymore,
    so this only clears out the old ones."""
    stale = session.scalars(
        select(Server).where(
            Server.is_test.is_(True), Server.created_at < utc_now() - SHORT_LIVED_FOR
        )
    ).all()
    codes = []
    character_ids = []
    for server in stale:
        character_ids += delete_game_data(session, server)
        codes.append(server.code)
        session.delete(server)
    session.commit()
    for character_id in character_ids:
        delete_quietly(files, str(character_id))
    return CleanupResponse(deleted=sorted(codes))
