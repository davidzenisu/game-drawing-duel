"""Your server's feedback board: ideas and bug reports the players post,
and upvote. Only the players of the same server see them. Authors remove
their own; server admins (`auth.ADMIN_PERMISSION`) remove any.

Server admins also set a suggestion's status: open (the default), in
progress, rejected or in review. Once in review, its author confirms it's
fixed: it's done, and they get a pull as a gift (`app.gifts`)."""

import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.orm import Session, selectinload

from app import gifts
from app.auth import ADMIN_PERMISSION, CurrentPlayer, TokenClaims
from app.deps import Code, DbSession, load_server, your_seat
from app.models import Server, ServerSeat, Suggestion, SuggestionVote
from app.schemas import (
    SuggestionResponse,
    SuggestionStatusChange,
    SuggestionSubmit,
)

router = APIRouter(prefix="/servers", tags=["suggestions"])

# The pulls its author gets once they confirm their suggestion is fixed.
FIXED_REWARD_PULLS = 1


def fixed_message(title: str) -> str:
    """The message of the gift for a suggestion its author confirmed."""
    return f"{title} has been fixed. Thank you for reporting it."


def _response(
    suggestion: Suggestion, server: Server, seat: ServerSeat, claims: TokenClaims
) -> SuggestionResponse:
    names = {s.id: s.name for s in server.seats}
    return SuggestionResponse(
        id=suggestion.id,
        kind=suggestion.kind,
        title=suggestion.title,
        description=suggestion.description,
        status=suggestion.status,
        author=names.get(suggestion.author_seat_id, "?"),
        created_at=suggestion.created_at,
        votes=len(suggestion.votes),
        voted=any(v.seat_id == seat.id for v in suggestion.votes),
        yours=suggestion.author_seat_id == seat.id,
        removable=_can_remove(suggestion, seat, claims),
    )


def _can_remove(suggestion: Suggestion, seat: ServerSeat, claims: TokenClaims) -> bool:
    """Its author can remove it, and server admins any."""
    return (
        suggestion.author_seat_id == seat.id
        or ADMIN_PERMISSION in claims["permissions"]
    )


def _board(code: str, player: CurrentPlayer, session: Session):
    """The server with `code` and your seat in it, at any phase."""
    server = load_server(session, code)
    return server, your_seat(server, player.id)


def _suggestion(session: Session, server: Server, suggestion_id: uuid.UUID) -> Suggestion:
    suggestion = session.scalar(
        select(Suggestion)
        .where(Suggestion.id == suggestion_id, Suggestion.server_id == server.id)
        .options(selectinload(Suggestion.votes))
    )
    if suggestion is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such suggestion")
    return suggestion


@router.get("/{code}/suggestions", response_model=list[SuggestionResponse])
def get_suggestions(
    code: Code, player: CurrentPlayer, claims: TokenClaims, session: DbSession
) -> list[SuggestionResponse]:
    """The server's suggestions, most upvoted first, then newest first."""
    server, seat = _board(code, player, session)
    suggestions = session.scalars(
        select(Suggestion)
        .where(Suggestion.server_id == server.id)
        .options(selectinload(Suggestion.votes))
    ).all()
    ranked = sorted(
        suggestions, key=lambda s: (len(s.votes), s.created_at), reverse=True
    )
    return [_response(s, server, seat, claims) for s in ranked]


@router.post(
    "/{code}/suggestions",
    response_model=SuggestionResponse,
    status_code=status.HTTP_201_CREATED,
)
def post_suggestion(
    code: Code,
    body: SuggestionSubmit,
    player: CurrentPlayer,
    claims: TokenClaims,
    session: DbSession,
) -> SuggestionResponse:
    """Posts an idea or a bug report on the server's board."""
    server, seat = _board(code, player, session)
    suggestion = Suggestion(
        server_id=server.id,
        author_seat_id=seat.id,
        kind=body.kind,
        title=body.title,
        description=body.description,
    )
    session.add(suggestion)
    session.commit()
    return _response(_suggestion(session, server, suggestion.id), server, seat, claims)


@router.put("/{code}/suggestions/{suggestion_id}/vote", response_model=SuggestionResponse)
def upvote(
    code: Code,
    suggestion_id: uuid.UUID,
    player: CurrentPlayer,
    claims: TokenClaims,
    session: DbSession,
) -> SuggestionResponse:
    """Upvotes a suggestion, once; not your own. Upvoting again changes
    nothing."""
    server, seat = _board(code, player, session)
    suggestion = _suggestion(session, server, suggestion_id)
    if suggestion.author_seat_id == seat.id:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="You can't upvote your own suggestion",
        )
    if not any(v.seat_id == seat.id for v in suggestion.votes):
        suggestion.votes.append(SuggestionVote(seat_id=seat.id))
        session.commit()
    return _response(_suggestion(session, server, suggestion_id), server, seat, claims)


@router.delete(
    "/{code}/suggestions/{suggestion_id}/vote", response_model=SuggestionResponse
)
def take_back_vote(
    code: Code,
    suggestion_id: uuid.UUID,
    player: CurrentPlayer,
    claims: TokenClaims,
    session: DbSession,
) -> SuggestionResponse:
    """Takes your upvote back, if you gave one."""
    server, seat = _board(code, player, session)
    suggestion = _suggestion(session, server, suggestion_id)
    for vote in [v for v in suggestion.votes if v.seat_id == seat.id]:
        suggestion.votes.remove(vote)
    session.commit()
    return _response(_suggestion(session, server, suggestion_id), server, seat, claims)


@router.delete(
    "/{code}/suggestions/{suggestion_id}", status_code=status.HTTP_204_NO_CONTENT
)
def remove_suggestion(
    code: Code,
    suggestion_id: uuid.UUID,
    player: CurrentPlayer,
    claims: TokenClaims,
    session: DbSession,
) -> None:
    """Removes a suggestion and its upvotes: your own, or any for server
    admins."""
    server, seat = _board(code, player, session)
    suggestion = _suggestion(session, server, suggestion_id)
    if not _can_remove(suggestion, seat, claims):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail="Only its author or a server admin can remove a suggestion",
        )
    session.delete(suggestion)
    session.commit()


@router.put(
    "/{code}/suggestions/{suggestion_id}/status", response_model=SuggestionResponse
)
def set_status(
    code: Code,
    suggestion_id: uuid.UUID,
    body: SuggestionStatusChange,
    player: CurrentPlayer,
    claims: TokenClaims,
    session: DbSession,
) -> SuggestionResponse:
    """Sets a suggestion's status, for server admins: open, in progress,
    rejected or in review. A done one keeps its status."""
    server, seat = _board(code, player, session)
    if ADMIN_PERMISSION not in claims["permissions"]:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail="Only a server admin can set a suggestion's status",
        )
    suggestion = _suggestion(session, server, suggestion_id)
    if suggestion.status == "done":
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="This suggestion is done already"
        )
    suggestion.status = body.status
    session.commit()
    return _response(_suggestion(session, server, suggestion_id), server, seat, claims)


@router.post(
    "/{code}/suggestions/{suggestion_id}/fixed", response_model=SuggestionResponse
)
def confirm_fixed(
    code: Code,
    suggestion_id: uuid.UUID,
    player: CurrentPlayer,
    claims: TokenClaims,
    session: DbSession,
) -> SuggestionResponse:
    """Confirms your suggestion in review is fixed: it's done, and you get
    a pull as a gift to accept. Only once."""
    server, seat = _board(code, player, session)
    suggestion = _suggestion(session, server, suggestion_id)
    if suggestion.author_seat_id != seat.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail="Only its author can confirm a suggestion is fixed",
        )
    # Only from in review, and once, even on two devices at once.
    done = session.execute(
        update(Suggestion)
        .where(Suggestion.id == suggestion.id, Suggestion.status == "in_review")
        .values(status="done")
    )
    if done.rowcount == 0:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="This suggestion isn't in review"
        )
    # Commits the status with the gift.
    gifts.send(
        session,
        sender_id=None,
        message=fixed_message(suggestion.title),
        pulls=FIXED_REWARD_PULLS,
        server=server,
        positions=[seat.position],
    )
    session.expire_all()
    return _response(_suggestion(session, server, suggestion_id), server, seat, claims)
