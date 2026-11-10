import uuid

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import CurrentPlayer
from app.deps import DbSession
from app.models import Character, Player, ServerSeat
from app.schemas import SketchData
from app.sketch_svg import render_svg
from app.storage import FileNotFound, Files, FileStore, StorageUnavailable

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
    return Response(
        _load_sketch(character_id, player, session, files),
        media_type="application/json",
        headers=_FOREVER,
    )


@router.get(
    "/{character_id}/sketch.svg",
    response_class=Response,
    responses={200: {"content": {"image/svg+xml": {}}}},
)
def get_sketch_svg(
    character_id: uuid.UUID, player: CurrentPlayer, session: DbSession, files: Files
) -> Response:
    """The character's drawing as an SVG image, drawn like the app draws it on
    its cardboard card: to look at a drawing outside the app. For the players of
    its server, cached for good like the strokes."""
    data = _load_sketch(character_id, player, session, files)
    return Response(
        render_svg(SketchData.model_validate_json(data)),
        media_type="image/svg+xml",
        headers=_FOREVER,
    )


_FOREVER = {"Cache-Control": "private, max-age=31536000, immutable"}


def _load_sketch(
    character_id: uuid.UUID, player: Player, session: Session, files: FileStore
) -> bytes:
    """The stored strokes of a character of one of the player's servers."""
    character = session.scalar(
        select(Character)
        .join(ServerSeat, ServerSeat.server_id == Character.server_id)
        .where(Character.id == character_id, ServerSeat.player_id == player.id)
    )
    if character is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such character")
    try:
        return files.download(str(character.id))
    except FileNotFound as error:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="The drawing is missing"
        ) from error
    except StorageUnavailable as error:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="Couldn't load the drawing"
        ) from error
