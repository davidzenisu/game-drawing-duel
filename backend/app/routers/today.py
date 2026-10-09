"""The daily loop: today's prompt and challenger, and moving days on."""

import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import days
from app.auth import CurrentPlayer
from app.drawings import save_character
from app.models import (
    ChallengerPrompt,
    Character,
    DayEnd,
    PullGrant,
    Server,
    ServerSeat,
)
from app.routers.pool import require_launched
from app.routers.servers import Code, DbSession, load_server, your_seat
from app.routers.setup import character_response
from app.rules import Rarity, theme_of_day
from app.schemas import (
    ChallengerSubmit,
    PromptSubmit,
    PromptToDrawResponse,
    TodayResponse,
    YourPrompt,
)
from app.storage import Files

router = APIRouter(prefix="/servers", tags=["today"])


def _running(session: Session, code: str, player_id: uuid.UUID):
    server = load_server(session, code)
    seat = your_seat(server, player_id)
    require_launched(server)
    return server, seat


def _challenger(session: Session, seat: ServerSeat, day: int) -> Character | None:
    return session.scalar(
        select(Character).where(
            Character.artist_seat_id == seat.id, Character.day == day
        )
    )


def _today(session: Session, server: Server, seat: ServerSeat) -> TodayResponse:
    day = days.current_day(server)
    written = session.scalar(
        select(ChallengerPrompt).where(
            ChallengerPrompt.author_seat_id == seat.id, ChallengerPrompt.day == day
        )
    )
    to_draw = days.prompt_to_draw(session, server, day, seat)
    drawn = _challenger(session, seat, day)
    ended = (
        session.scalars(
            select(ServerSeat.position)
            .join(DayEnd, DayEnd.seat_id == ServerSeat.id)
            .where(ServerSeat.server_id == server.id, DayEnd.day == day)
            .order_by(ServerSeat.position)
        ).all()
        if server.is_test
        else []
    )
    return TodayResponse(
        day=day,
        theme=theme_of_day(day).value,
        prompt=YourPrompt(
            subject_position=days.prompt_subject(server, day, seat).position,
            title=written.title if written else None,
        ),
        to_draw=None
        if to_draw is None
        else PromptToDrawResponse(
            author_position=to_draw.author.position,
            subject_position=to_draw.subject.position,
            title=to_draw.title,
            theme=to_draw.theme.value,
            premade=to_draw.premade,
            challenger=character_response(drawn) if drawn else None,
        ),
        day_ended=list(ended),
    )


@router.get("/{code}/today", response_model=TodayResponse)
def get_today(code: Code, player: CurrentPlayer, session: DbSession) -> TodayResponse:
    """Today's day and theme, your prompt to write and your prompt to draw."""
    server, seat = _running(session, code, player.id)
    return _today(session, server, seat)


@router.post("/{code}/today/prompt", response_model=TodayResponse)
def write_prompt(
    code: Code, body: PromptSubmit, player: CurrentPlayer, session: DbSession
) -> TodayResponse:
    """Step 1: writes today's challenger title; the next player draws it
    tomorrow. Once a day."""
    server, seat = _running(session, code, player.id)
    day = days.current_day(server)
    session.add(
        ChallengerPrompt(
            author_seat_id=seat.id,
            day=day,
            subject_seat_id=days.prompt_subject(server, day, seat).id,
            title=body.title,
            theme=theme_of_day(day).value,
        )
    )
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="You wrote today's prompt already"
        ) from error
    return _today(session, server, seat)


@router.put("/{code}/today/challenger", response_model=TodayResponse)
def draw_challenger(
    code: Code,
    body: ChallengerSubmit,
    player: CurrentPlayer,
    session: DbSession,
    files: Files,
) -> TodayResponse:
    """Step 2: draws today's prompt. The challenger joins the pool as a hero
    and earns a pull. Once a day."""
    server, seat = _running(session, code, player.id)
    day = days.current_day(server)
    prompt = days.prompt_to_draw(session, server, day, seat)
    if prompt is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="There's no prompt to draw today"
        )
    if _challenger(session, seat, day) is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="You drew today's challenger already"
        )
    character = Character(
        id=uuid.uuid4(),
        server_id=server.id,
        artist=seat,
        subject=prompt.subject,
        title=prompt.title,
        rarity=Rarity.HERO.value,
        prompt="challenger",
        day=day,
        theme=prompt.theme.value,
    )

    def reward() -> None:
        # The only pull to earn each day.
        session.add(PullGrant(seat_id=seat.id, reason=f"challenger:day-{day}"))

    save_character(
        session,
        files,
        server,
        character,
        body.sketch,
        kind="challenger",
        conflict="You drew today's challenger already",
        before_insert=reward,
    )
    return _today(session, server, seat)


def _test_session(server: Server) -> None:
    if not server.is_test:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="Only test sessions move on before midnight UTC",
        )


def _advance(session: Session, server: Server, day: int) -> None:
    """Moves a test session from `day` to the next, once."""
    session.execute(
        update(Server)
        .where(Server.id == server.id, Server.test_day == day)
        .values(test_day=day + 1)
    )


@router.post("/{code}/today/end", response_model=TodayResponse)
def end_day(code: Code, player: CurrentPlayer, session: DbSession) -> TodayResponse:
    """Test sessions: you're done for today. Once everyone is, the next day
    starts."""
    server, seat = _running(session, code, player.id)
    _test_session(server)
    # Players ending the day at once wait for each other here, so the last
    # one sees everyone else's and moves the day on.
    session.scalar(select(Server.id).where(Server.id == server.id).with_for_update())
    session.refresh(server)
    day = days.current_day(server)
    if not session.scalar(
        select(DayEnd.id).where(DayEnd.seat_id == seat.id, DayEnd.day == day)
    ):
        session.add(DayEnd(seat_id=seat.id, day=day))
        session.flush()
    ended = set(
        session.scalars(
            select(DayEnd.seat_id).where(
                DayEnd.day == day,
                DayEnd.seat_id.in_([s.id for s in server.seats]),
            )
        )
    )
    if all(s.id in ended for s in days.active_seats(server)):
        _advance(session, server, day)
    session.commit()
    session.refresh(server)
    return _today(session, server, seat)


@router.post("/{code}/days/next", response_model=TodayResponse)
def next_day(code: Code, player: CurrentPlayer, session: DbSession) -> TodayResponse:
    """Test sessions: the admin starts the next day for everyone."""
    server, seat = _running(session, code, player.id)
    _test_session(server)
    if server.admin_id != player.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, detail="Only the admin can start the next day"
        )
    _advance(session, server, days.current_day(server))
    session.commit()
    session.refresh(server)
    return _today(session, server, seat)
