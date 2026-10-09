import uuid

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select

from app.auth import CurrentPlayer
from app.models import Character, ServerSeat
from app.routers.servers import DbSession
from app.storage import FileNotFound, Files, StorageUnavailable

router = APIRouter(prefix="/characters", tags=["characters"])


@router.get(
    "/{character_id}/sketch",
    response_class=Response,
    responses={200: {"content": {"application/json": {}}}},
)
def get_sketch(
    character_id: uuid.UUID, player: CurrentPlayer, session: DbSession, files: Files
) -> Response:
    """The strokes of a character, for the players of its server.

    A character never changes (redrawing creates a new one), so it can be
    cached for good.
    """
    character = session.scalar(
        select(Character)
        .join(ServerSeat, ServerSeat.server_id == Character.server_id)
        .where(Character.id == character_id, ServerSeat.player_id == player.id)
    )
    if character is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such character")
    try:
        data = files.download(str(character.id))
    except FileNotFound as error:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="The drawing is missing"
        ) from error
    except StorageUnavailable as error:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="Couldn't load the drawing"
        ) from error
    return Response(
        data,
        media_type="application/json",
        headers={"Cache-Control": "private, max-age=31536000, immutable"},
    )
