"""The Arena (`app.arena`): today's matchup and voting on it."""

from fastapi import APIRouter, HTTPException, status
from sqlalchemy.orm import Session

from app import arena, days, finale, rules, stars
from app.auth import CurrentPlayer
from app.deps import Code, DbSession, running_game
from app.models import Server, ServerSeat
from app.responses import character_response
from app.schemas import (
    ArenaHeroResponse,
    ArenaResponse,
    ArenaStatus,
    ArenaVoteSubmit,
)

router = APIRouter(prefix="/servers", tags=["arena"])


def arena_status(state: arena.ArenaState) -> ArenaStatus | None:
    if state.week is None:
        return None
    return ArenaStatus(
        week=state.week,
        ends_on=arena.ends_on(state.week),
        challengers=state.challengers,
        votes_today=state.votes_today,
        cap=state.cap,
        pack=state.pack,
        pack_stars=rules.ARENA_PACK_STARS,
        rewarded=state.rewarded,
    )


def arena_heroes(session: Session, server: Server) -> list[ArenaHeroResponse]:
    return [
        ArenaHeroResponse(
            character=character_response(hero.character),
            week=hero.week,
            place=hero.place,
        )
        for hero in arena.latest_winners(session, server)
    ]


def _response(session: Session, server: Server, seat: ServerSeat) -> ArenaResponse:
    state = arena.state(session, server, seat, days.current_day(server))
    return ArenaResponse(
        status=arena_status(state),
        matchup=None
        if state.matchup is None
        else [character_response(c) for c in state.matchup],
        next_matchup=None
        if state.next_matchup is None
        else [character_response(c) for c in state.next_matchup],
        stars=stars.balance(session, seat.id),
    )


@router.get("/{code}/arena", response_model=ArenaResponse)
def get_arena(code: Code, player: CurrentPlayer, session: DbSession) -> ArenaResponse:
    """Your Arena today, with the next matchup to vote on."""
    server, seat = running_game(session, code, player.id)
    finale.settle(session, server)
    return _response(session, server, seat)


@router.post("/{code}/arena/votes", response_model=ArenaResponse)
def vote(
    code: Code, body: ArenaVoteSubmit, player: CurrentPlayer, session: DbSession
) -> ArenaResponse:
    """Votes on a matchup: for one of its challengers, or a draw without a
    winner. Answers with the next matchup."""
    server, seat = running_game(session, code, player.id)
    finale.settle(session, server)
    first, second = body.challenger_ids
    try:
        arena.vote(
            session,
            server,
            seat,
            days.current_day(server),
            (first, second),
            body.winner_id,
        )
    except arena.VoteRejected as error:
        raise HTTPException(status.HTTP_409_CONFLICT, detail=str(error)) from error
    return _response(session, server, seat)
