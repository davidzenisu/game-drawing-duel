"""Saving a drawn character: its sketch as a file, then its database row."""

import logging
from collections.abc import Callable

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import Character, Server
from app.schemas import SketchData
from app.storage import FileStore, StorageUnavailable, delete_quietly

logger = logging.getLogger(__name__)


def save_character(
    session: Session,
    files: FileStore,
    server: Server,
    character: Character,
    sketch: SketchData,
    *,
    kind: str,
    conflict: str,
    before_insert: Callable[[], None] | None = None,
) -> None:
    """Stores `sketch` as a file named after the character's id, labelled with
    `kind` and the character's details, then commits the character.

    `before_insert` runs in the same transaction, e.g. to remove the drawing it
    replaces. If the commit fails the file is deleted again; a conflicting
    row answers 409 with `conflict`.
    """
    try:
        files.upload(
            str(character.id),
            sketch.model_dump_json().encode(),
            content_type="application/json",
            metadata={
                "kind": kind,
                "server": server.code,
                "prompt": character.prompt,
                "rarity": character.rarity,
                "artist_position": str(character.artist.position),
                "subject_position": str(character.subject.position),
            },
        )
    except StorageUnavailable as error:
        logger.exception("Storing a drawing failed")
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="Couldn't store the drawing"
        ) from error
    try:
        if before_insert is not None:
            before_insert()
        session.add(character)
        session.commit()
    except Exception as error:
        session.rollback()
        delete_quietly(files, str(character.id))
        if isinstance(error, IntegrityError):
            raise HTTPException(status.HTTP_409_CONFLICT, detail=conflict) from error
        raise
