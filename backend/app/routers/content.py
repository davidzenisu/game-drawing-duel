"""The prompt hints and premade titles, for the accounts with the content
permission (`auth.CONTENT_PERMISSION`).

New rows are used from the day after they were added. Retiring a row keeps it
for the rest of the day, so the picks of a day never change (see
`days._options`); a retired row stays in the database but isn't listed.
"""

import uuid
from dataclasses import dataclass

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import require_content_editor
from app.database import utc_now
from app.models import PremadeTitle, ThemeHint
from app.routers.servers import DbSession
from app.rules import MAX_TITLE_LENGTH, Theme
from app.schemas import ContentAdd, ContentAdded, ContentItem

router = APIRouter(
    prefix="/content",
    tags=["content"],
    dependencies=[Depends(require_content_editor)],
)


@dataclass(frozen=True)
class _Kind:
    model: type[ThemeHint] | type[PremadeTitle]
    # The column with the text.
    column: str
    max_length: int | None
    name: str


HINTS = _Kind(ThemeHint, "text", None, "hint")
TITLES = _Kind(PremadeTitle, "title", MAX_TITLE_LENGTH, "premade title")


def _item(kind: _Kind, row: ThemeHint | PremadeTitle) -> ContentItem:
    return ContentItem(
        id=row.id,
        theme=Theme(row.theme),
        text=getattr(row, kind.column),
        created_at=row.created_at,
    )


def _in_use(session: Session, kind: _Kind, theme: Theme | None) -> list:
    query = select(kind.model).where(kind.model.retired_at.is_(None))
    if theme is not None:
        query = query.where(kind.model.theme == theme.value)
    return list(
        session.scalars(query.order_by(kind.model.theme, kind.model.created_at))
    )


def _list(session: Session, kind: _Kind, theme: Theme | None) -> list[ContentItem]:
    return [_item(kind, row) for row in _in_use(session, kind, theme)]


def _add(session: Session, kind: _Kind, body: ContentAdd) -> ContentAdded:
    texts = [text.strip() for text in body.texts]
    if any(not text for text in texts):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, detail=f"A {kind.name} can't be empty"
        )
    if kind.max_length and any(len(text) > kind.max_length for text in texts):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"A {kind.name} has at most {kind.max_length} characters",
        )
    known = {
        getattr(row, kind.column).casefold()
        for row in _in_use(session, kind, body.theme)
    }
    added, skipped = [], []
    for text in texts:
        if text.casefold() in known:
            skipped.append(text)
            continue
        known.add(text.casefold())
        row = kind.model(theme=body.theme.value, **{kind.column: text})
        session.add(row)
        added.append(row)
    session.commit()
    return ContentAdded(added=[_item(kind, row) for row in added], skipped=skipped)


def _retire(session: Session, kind: _Kind, row_id: uuid.UUID) -> None:
    row = session.get(kind.model, row_id)
    if row is None or row.retired_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=f"No such {kind.name}")
    row.retired_at = utc_now()
    session.commit()


@router.get("/hints", response_model=list[ContentItem])
def list_hints(session: DbSession, theme: Theme | None = None) -> list[ContentItem]:
    """The prompt hints in use, optionally of one theme."""
    return _list(session, HINTS, theme)


@router.post(
    "/hints", response_model=ContentAdded, status_code=status.HTTP_201_CREATED
)
def add_hints(body: ContentAdd, session: DbSession) -> ContentAdded:
    """Adds prompt hints to a theme, used from tomorrow on. Hints the theme
    has already are skipped."""
    return _add(session, HINTS, body)


@router.delete("/hints/{hint_id}", status_code=status.HTTP_204_NO_CONTENT)
def retire_hint(hint_id: uuid.UUID, session: DbSession) -> None:
    """Retires a prompt hint: it's still used for the rest of the day."""
    _retire(session, HINTS, hint_id)


@router.get("/premade-titles", response_model=list[ContentItem])
def list_premade_titles(
    session: DbSession, theme: Theme | None = None
) -> list[ContentItem]:
    """The premade titles in use, optionally of one theme."""
    return _list(session, TITLES, theme)


@router.post(
    "/premade-titles", response_model=ContentAdded, status_code=status.HTTP_201_CREATED
)
def add_premade_titles(body: ContentAdd, session: DbSession) -> ContentAdded:
    """Adds premade titles to a theme, used from tomorrow on. Titles the
    theme has already are skipped."""
    return _add(session, TITLES, body)


@router.delete("/premade-titles/{title_id}", status_code=status.HTTP_204_NO_CONTENT)
def retire_premade_title(title_id: uuid.UUID, session: DbSession) -> None:
    """Retires a premade title: it's still used for the rest of the day."""
    _retire(session, TITLES, title_id)
