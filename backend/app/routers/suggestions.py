"""Your server's feedback board: ideas and bug reports the players post,
and upvote. Only the players of the same server see them. Authors remove
their own; server admins (`auth.ADMIN_PERMISSION`) remove any."""

import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.auth import ADMIN_PERMISSION, CurrentPlayer, TokenClaims
from app.deps import Code, DbSession, load_server, your_seat
from app.models import Server, ServerSeat, Suggestion, SuggestionVote
from app.schemas import SuggestionResponse, SuggestionSubmit

router = APIRouter(prefix="/servers", tags=["suggestions"])


def _response(
    suggestion: Suggestion, server: Server, seat: ServerSeat, claims: TokenClaims
) -> SuggestionResponse:
    names = {s.id: s.name for s in server.seats}
    return SuggestionResponse(
        id=suggestion.id,
        kind=suggestion.kind,
        title=suggestion.title,
        description=suggestion.description,
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
