"""The Arena (`app.arena`): today's matchup, voting on it, and the latest
decided Arena's ranking."""

from fastapi import APIRouter, HTTPException, status
from sqlalchemy.orm import Session

from app import arena, days, finale, rules, stars
from app.auth import CurrentPlayer, Reveal
from app.deps import Code, DbSession, running_game
from app.models import Server, ServerSeat
from app.responses import character_response
from app.schemas import (
    ArenaHeroResponse,
    ArenaRanked,
    ArenaRankingResponse,
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


def _response(
    session: Session, seat: ServerSeat, state: arena.ArenaState
) -> ArenaResponse:
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
    return _response(
        session, seat, arena.state(session, server, seat, days.current_day(server))
    )


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
        after = arena.vote(
            session,
            server,
            seat,
            days.current_day(server),
            (first, second),
            body.winner_id,
        )
    except arena.VoteRejected as error:
        raise HTTPException(status.HTTP_409_CONFLICT, detail=str(error)) from error
    return _response(session, seat, after)


@router.get("/{code}/arena/ranking", response_model=ArenaRankingResponse | None)
def get_arena_ranking(
    code: Code, player: CurrentPlayer, session: DbSession, reveal: Reveal
) -> ArenaRankingResponse | None:
    """The latest decided Arena, best first, with its winners. Null before
    the first one is decided, and always in speed mode.

    With `reveal`, for accounts with the admin permission, the Arena open
    today instead, ranked by its votes so far, without winners yet, for
    debugging. Null in the first week."""
    server, _ = running_game(session, code, player.id)
    finale.settle(session, server)
    week = (
        arena.open_week(server, days.current_day(server))
        if reveal
        else arena.latest_week(session, server)
    )
    if week is None:
        return None
    winners = {h.character_id: h for h in arena.winners_of(session, server, week)}
    return ArenaRankingResponse(
        week=week,
        ends_on=arena.ends_on(week),
        min_matchups=rules.ARENA_MIN_MATCHUPS,
        challengers=[
            ArenaRanked(
                character=character_response(s.challenger),
                place=place,
                hero_rarity=winners[s.challenger.id].rarity
                if s.challenger.id in winners
                else None,
                rating=s.rating,
                score=s.score,
                matchups=s.matchups,
                qualified=s.qualified,
            )
            for place, s in enumerate(arena.ranking(session, server, week), 1)
        ],
    )
