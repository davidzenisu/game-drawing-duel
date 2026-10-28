"""The prompt hints, each a description with its premade title, and the
starter prompts of the setup drawings, for the accounts with the content
permission (`auth.CONTENT_PERMISSION`).

New hints are used from the day after they were added. Retiring a hint keeps
it for the rest of the day, so the picks of a day never change (see
`days.hints_on`); a retired hint stays in the database but isn't listed.
Starter prompts are given out from the next setup on, and retired ones not
anymore (see `setup.give_hints`).
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import require_content_editor
from app.database import utc_now
from app.models import SetupHint, ThemeHint
from app.routers.servers import DbSession
from app.rules import SetupPrompt, Theme
from app.schemas import (
    ContentAdd,
    ContentAdded,
    ContentItem,
    SetupHintAdd,
    SetupHintAdded,
    SetupHintItem,
)

router = APIRouter(
    prefix="/content",
    tags=["content"],
    dependencies=[Depends(require_content_editor)],
)


def _item(hint: ThemeHint) -> ContentItem:
    return ContentItem(
        id=hint.id,
        theme=Theme(hint.theme),
        text=hint.text,
        premade_title=hint.premade_title,
        created_at=hint.created_at,
    )


def _in_use(session: Session, theme: Theme | None) -> list[ThemeHint]:
    query = select(ThemeHint).where(ThemeHint.retired_at.is_(None))
    if theme is not None:
        query = query.where(ThemeHint.theme == theme.value)
    return list(session.scalars(query.order_by(ThemeHint.theme, ThemeHint.created_at)))


@router.get("/hints", response_model=list[ContentItem])
def list_hints(session: DbSession, theme: Theme | None = None) -> list[ContentItem]:
    """The prompt hints in use, optionally of one theme."""
    return [_item(hint) for hint in _in_use(session, theme)]


@router.post("/hints", response_model=ContentAdded, status_code=status.HTTP_201_CREATED)
def add_hints(body: ContentAdd, session: DbSession) -> ContentAdded:
    """Adds prompt hints to a theme, each with its premade title, used from
    tomorrow on. Descriptions the theme has already are skipped."""
    known = {hint.text.casefold() for hint in _in_use(session, body.theme)}
    added, skipped = [], []
    for draft in body.hints:
        if draft.text.casefold() in known:
            skipped.append(draft.text)
            continue
        known.add(draft.text.casefold())
        hint = ThemeHint(
            theme=body.theme.value, text=draft.text, premade_title=draft.premade_title
        )
        session.add(hint)
        added.append(hint)
    session.commit()
    return ContentAdded(added=[_item(hint) for hint in added], skipped=skipped)


@router.delete("/hints/{hint_id}", status_code=status.HTTP_204_NO_CONTENT)
def retire_hint(hint_id: uuid.UUID, session: DbSession) -> None:
    """Retires a prompt hint: it's still used for the rest of the day."""
    hint = session.get(ThemeHint, hint_id)
    if hint is None or hint.retired_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such hint")
    hint.retired_at = utc_now()
    session.commit()


def _setup_item(hint: SetupHint) -> SetupHintItem:
    return SetupHintItem(
        id=hint.id,
        prompt=SetupPrompt(hint.prompt),
        text=hint.text,
        created_at=hint.created_at,
    )


def _setup_in_use(session: Session, prompt: SetupPrompt | None) -> list[SetupHint]:
    query = select(SetupHint).where(SetupHint.retired_at.is_(None))
    if prompt is not None:
        query = query.where(SetupHint.prompt == prompt.value)
    return list(session.scalars(query.order_by(SetupHint.prompt, SetupHint.created_at)))


@router.get("/setup-hints", response_model=list[SetupHintItem])
def list_setup_hints(
    session: DbSession, prompt: SetupPrompt | None = None
) -> list[SetupHintItem]:
    """The starter prompts in use, optionally of one setup prompt type."""
    return [_setup_item(hint) for hint in _setup_in_use(session, prompt)]


@router.post(
    "/setup-hints",
    response_model=SetupHintAdded,
    status_code=status.HTTP_201_CREATED,
)
def add_setup_hints(body: SetupHintAdd, session: DbSession) -> SetupHintAdded:
    """Adds starter prompts to a setup prompt type, given out from the next
    setup on. Texts the type has already are skipped."""
    known = {hint.text.casefold() for hint in _setup_in_use(session, body.prompt)}
    added, skipped = [], []
    for text in body.texts:
        if text.casefold() in known:
            skipped.append(text)
            continue
        known.add(text.casefold())
        hint = SetupHint(prompt=body.prompt.value, text=text)
        session.add(hint)
        added.append(hint)
    session.commit()
    return SetupHintAdded(added=[_setup_item(h) for h in added], skipped=skipped)


@router.delete("/setup-hints/{hint_id}", status_code=status.HTTP_204_NO_CONTENT)
def retire_setup_hint(hint_id: uuid.UUID, session: DbSession) -> None:
    """Retires a starter prompt: setups started from now on don't get it."""
    hint = session.get(SetupHint, hint_id)
    if hint is None or hint.retired_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such starter prompt")
    hint.retired_at = utc_now()
    session.commit()
