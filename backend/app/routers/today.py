"""The daily loop: today's prompt and challenger, and moving days on."""

import random
import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import day_flow, days, fights, finale, speed, stars, win_rates
from app.auth import CurrentPlayer
from app.deps import Code, DbSession, running_game
from app.drawings import save_character
from app.models import (
    ChallengerPrompt,
    Character,
    DayEnd,
    Fight,
    Hurry,
    PullGrant,
    Server,
    ServerSeat,
)
from app.responses import character_response
from app.rules import (
    BOOST_MAX_PER_CHALLENGER,
    BOOST_STARS,
    SPEED_DAYS,
    STARS_FOR_CHALLENGER,
    STARS_FOR_PROMPT,
    WIN_RATE_MIN_FIGHTS,
    Rarity,
    hurry_hits,
)
from app.schemas import (
    BoostStep,
    BoostSubmit,
    BoostTarget,
    ChallengerResponse,
    ChallengerSubmit,
    FightDay,
    FighterResponse,
    FightersSubmit,
    FightResponse,
    FightStep,
    HurrySubmit,
    IncomingHurry,
    OutcomeResponse,
    PromptSubmit,
    PromptToDrawResponse,
    RankedChallenger,
    RankingResponse,
    TodayResponse,
    WeeklyHeroResponse,
    WinRate,
    WinRatesResponse,
    YourPrompt,
)
from app.storage import Files

router = APIRouter(prefix="/servers", tags=["today"])


def _fight_response(session: Session, server: Server, fight: Fight) -> FightResponse:
    positions = {s.id: s.position for s in server.seats}
    result = fights.outcome(session, fight)
    return FightResponse(
        id=fight.id,
        day=fight.day,
        owner_position=positions[fight.owner_seat_id],
        challenger=character_response(fight.challenger),
        fighters=[
            FighterResponse(
                character=character_response(f.character),
                upgrades=f.upgrades.split(",") if f.upgrades else [],
                element=f.element,
                extra_stars=f.extra_stars,
            )
            for f in fight.fighters
        ],
        by_chance=fight.by_chance,
        outcome=OutcomeResponse(
            fighter_stars=result.fighter_stars,
            boost_stars=result.boosts,
            challenger_stars=result.challenger_stars,
            fighter_extra_stars=result.fighter_extra_stars,
            challenger_extra_stars=result.challenger_extra_stars,
            fighters_win=result.fighters_win,
        ),
    )


def _today(session: Session, server: Server, seat: ServerSeat) -> TodayResponse:
    day = days.current_day(server)
    # Yesterday's boosts and fights nobody finished are needed for today's
    # fights, the results and the finale.
    fights.complete_boosts(session, server, day - 1)
    fights.complete_fights(session, server, day - 1)
    fights.decide_fights(session, server)
    finale.settle(session, server)
    written = session.scalar(
        select(ChallengerPrompt).where(
            ChallengerPrompt.author_seat_id == seat.id, ChallengerPrompt.day == day
        )
    )
    to_draw = days.prompt_to_draw(session, server, day, seat)
    drawn = days.drawn_challenger(session, seat, day)
    ended = (
        session.scalars(
            select(ServerSeat.position)
            .join(DayEnd, DayEnd.seat_id == ServerSeat.id)
            .where(ServerSeat.server_id == server.id, DayEnd.day == day)
            .order_by(ServerSeat.position)
        ).all()
        if server.is_test or speed.is_speed(server)
        else []
    )
    return TodayResponse(
        day=day,
        theme=days.theme_of(server, day).value,
        ends_at=speed.clock(server).ends_at if speed.is_speed(server) else None,
        prompt=YourPrompt(
            hint=days.prompt_hint(session, server, day, seat),
            theme=days.challenger_theme(server, day).value,
            subject_position=next(
                s.position for s in server.seats if s.id == written.subject_seat_id
            )
            if written
            else None,
            title=written.title if written else None,
        )
        if days.prompts_on(server, day)
        else None,
        to_draw=None
        if to_draw is None
        else PromptToDrawResponse(
            author_position=to_draw.author.position,
            subject_position=to_draw.subject.position,
            title=to_draw.title,
            theme=to_draw.theme.value,
            hint=to_draw.hint,
            premade=to_draw.premade,
            challenger=character_response(drawn) if drawn else None,
        ),
        fight=_fight_step(session, server, day, seat),
        boost=_boost_step(session, server, day, seat),
        boost_forfeited=fights.missed_drawing(session, server, day, seat),
        results=[
            _fight_response(session, server, f)
            for f in fights.fights_on(session, server, day - 1)
            if seat.id in {f.owner_seat_id, f.challenger.artist_seat_id}
        ],
        hurry_sent_to=_hurry_sent_to(session, server, seat, day),
        incoming_hurries=_incoming_hurries(session, server, seat, day),
        day_ended=list(ended),
        weekly_hero=_weekly_hero(session, server),
    )


def _boost_step(
    session: Session, server: Server, day: int, seat: ServerSeat
) -> BoostStep | None:
    targets = fights.boost_targets(session, server, day, seat)
    if not targets:
        return None
    given = fights.given_boosts(session, seat, day)
    return BoostStep(
        targets=[
            BoostTarget(challenger=character_response(c), stars=given.get(c.id, 0))
            for c in targets
        ],
        stars=BOOST_STARS,
        max_per_challenger=BOOST_MAX_PER_CHALLENGER,
    )


def _weekly_hero(session: Session, server: Server) -> WeeklyHeroResponse | None:
    hero = finale.latest_hero(session, server)
    if hero is None:
        return None
    return WeeklyHeroResponse(
        character=character_response(hero.character),
        day=hero.day,
        stars=hero.stars,
    )


def _hurry_sent_to(
    session: Session, server: Server, seat: ServerSeat, day: int
) -> int | None:
    """Who `seat` sent `day`'s hurry to: it hits the day after."""
    target = session.scalar(
        select(Hurry.target_seat_id).where(
            Hurry.sender_seat_id == seat.id, Hurry.day == day + 1
        )
    )
    return next((s.position for s in server.seats if s.id == target), None)


def _incoming_hurries(
    session: Session, server: Server, seat: ServerSeat, day: int
) -> list[IncomingHurry]:
    """The hurries hitting `seat`'s drawing on `day`, spread out in the
    order they were sent."""
    positions = {s.id: s.position for s in server.seats}
    hurries = session.scalars(
        select(Hurry)
        .where(Hurry.target_seat_id == seat.id, Hurry.day == day)
        .order_by(Hurry.sent_at, Hurry.id)
    ).all()
    hits = hurry_hits([hurry.at_fraction for hurry in hurries])
    return [
        IncomingHurry(by_position=positions[hurry.sender_seat_id], left_seconds=left)
        for hurry, left in zip(hurries, hits, strict=True)
    ]


def _fight_step(
    session: Session, server: Server, day: int, seat: ServerSeat
) -> FightStep | None:
    challenger = fights.fight_challenger(session, server, day, seat)
    if challenger is None:
        return None
    yours = fights.fight_of(session, seat, day)
    return FightStep(
        challenger=character_response(challenger),
        yours=None
        if yours is None
        else _fight_response(session, server, yours),
        resting=sorted(fights.resting(session, server, seat, day), key=str),
    )


@router.get("/{code}/today", response_model=TodayResponse)
def get_today(code: Code, player: CurrentPlayer, session: DbSession) -> TodayResponse:
    """Today's day and theme, your prompt to write and your prompt to draw."""
    server, seat = running_game(session, code, player.id)
    return _today(session, server, seat)


@router.post("/{code}/today/prompt", response_model=TodayResponse)
def write_prompt(
    code: Code, body: PromptSubmit, player: CurrentPlayer, session: DbSession
) -> TodayResponse:
    """Step 1: chooses the person who fits today's description best (anyone
    but yourself) and writes their challenger title; the next player draws
    it tomorrow. Earns stars (`rules.STARS_FOR_PROMPT`). Once a day."""
    server, seat = running_game(session, code, player.id)
    day = days.current_day(server)
    if not days.prompts_on(server, day):
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="No challenger prompts today"
        )
    subject = next(
        (s for s in server.seats if s.position == body.subject_position), None
    )
    if subject is None or not days.can_be_subject(seat, subject):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Choose another player of the server",
        )
    session.add(
        ChallengerPrompt(
            author_seat_id=seat.id,
            day=day,
            subject_seat_id=subject.id,
            title=body.title,
            theme=days.challenger_theme(server, day).value,
            hint=days.prompt_hint(session, server, day, seat),
        )
    )
    session.add(stars.grant(seat.id, f"prompt:day-{day}", STARS_FOR_PROMPT))
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="You wrote today's prompt already"
        ) from error
    day_flow.end_speed_day_if_done(session, server)
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
    and earns a pull and stars (`rules.STARS_FOR_CHALLENGER`). Once a day."""
    server, seat = running_game(session, code, player.id)
    day = days.current_day(server)
    prompt = days.prompt_to_draw(session, server, day, seat)
    if prompt is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="There's no prompt to draw today"
        )
    if days.drawn_challenger(session, seat, day) is not None:
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
        # Besides a won fight, the only pull to earn each day.
        session.add(PullGrant(seat_id=seat.id, reason=f"challenger:day-{day}"))
        session.add(
            stars.grant(seat.id, f"challenger:day-{day}", STARS_FOR_CHALLENGER)
        )

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
    day_flow.end_speed_day_if_done(session, server)
    return _today(session, server, seat)


@router.put("/{code}/today/fighters", response_model=TodayResponse)
def pick_fighters(
    code: Code, body: FightersSubmit, player: CurrentPlayer, session: DbSession
) -> TodayResponse:
    """Step 4: sends up to four of your characters against today's
    challenger, boosted yesterday. The stars decide right away: a win earns
    a pull (`fight:day-N`), or in speed mode one per challenger star
    (`fight:day-N:1`, …), and the challenger's stars as stars (`app.stars`).
    Once a day, and every character but the basic ones once a week."""
    server, seat = running_game(session, code, player.id)
    day = days.current_day(server)
    fights.complete_boosts(session, server, day - 1)
    # Last week's fights give this week's win rates.
    fights.complete_fights(session, server, day - 1)
    challenger = fights.fight_challenger(session, server, day, seat)
    if challenger is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="There's no challenger to fight today"
        )
    if len(set(body.character_ids)) != len(body.character_ids):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Pick every fighter once"
        )
    fighters = fights.owned_characters(session, seat, body.character_ids)
    if fighters is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="You can only send your own characters"
        )
    if fights.resting(session, server, seat, day) & set(body.character_ids):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="Every character fights once a week; they're back on Monday",
        )
    fight = fights.new_fight(session, seat, day, challenger, fighters)
    if fight.fighters_win:
        session.add_all(
            PullGrant(seat_id=seat.id, reason=reason)
            for reason in fights.win_rewards(server, day, fight)
        )
        session.add(
            stars.grant(seat.id, f"fight:day-{day}", fight.challenger_stars)
        )
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="You picked today's fighters already"
        ) from error
    day_flow.end_speed_day_if_done(session, server)
    return _today(session, server, seat)


@router.put("/{code}/today/boosts", response_model=TodayResponse)
def boost(
    code: Code, body: BoostSubmit, player: CurrentPlayer, session: DbSession
) -> TodayResponse:
    """Step 3: spreads your boost stars across today's challengers to boost,
    replacing the ones you gave today. Once the day is over, chance spreads
    the stars you left."""
    server, seat = running_game(session, code, player.id)
    day = days.current_day(server)
    given = {b.challenger_id: b.stars for b in body.boosts}
    if len(given) != len(body.boosts):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Boost every challenger once"
        )
    try:
        fights.set_boosts(session, server, day, seat, given)
    except fights.InvalidBoost as error:
        raise HTTPException(status.HTTP_409_CONFLICT, detail=str(error)) from error
    except IntegrityError as error:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="Your boosts changed at the same time"
        ) from error
    day_flow.end_speed_day_if_done(session, server)
    return _today(session, server, seat)


@router.post("/{code}/today/hurry", response_model=TodayResponse)
def send_hurry(
    code: Code, body: HurrySubmit, player: CurrentPlayer, session: DbSession
) -> TodayResponse:
    """Sends today's free hurry: it cuts the target's challenger drawing time
    tomorrow at a random moment, which they find out while drawing. Once a
    day, on the days before a drawing day."""
    server, seat = running_game(session, code, player.id)
    hits_on = days.current_day(server) + 1
    if not days.draws_on(server, hits_on) or (
        speed.is_speed(server) and speed.clock(server).over
    ):
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="Nobody draws a challenger tomorrow"
        )
    target = next(
        (s for s in days.active_seats(server) if s.position == body.target_position),
        None,
    )
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such player")
    if target.id == seat.id:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, detail="You can't hurry yourself"
        )
    session.add(
        Hurry(
            sender_seat_id=seat.id,
            target_seat_id=target.id,
            day=hits_on,
            at_fraction=random.random(),
        )
    )
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="You sent today's hurry already"
        ) from error
    return _today(session, server, seat)


def _day_controls(server: Server) -> None:
    if not (server.is_test or speed.is_speed(server)):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="Only test sessions and speed mode move on before midnight UTC",
        )


@router.post("/{code}/today/end", response_model=TodayResponse)
def end_day(code: Code, player: CurrentPlayer, session: DbSession) -> TodayResponse:
    """Test sessions and speed mode: you're done for today. Once everyone
    is, the next day starts."""
    server, seat = running_game(session, code, player.id)
    _day_controls(server)
    day_flow.end_day(session, server, seat)
    return _today(session, server, seat)


@router.post("/{code}/days/next", response_model=TodayResponse)
def next_day(code: Code, player: CurrentPlayer, session: DbSession) -> TodayResponse:
    """Test sessions and speed mode: the admin starts the next day for
    everyone."""
    server, seat = running_game(session, code, player.id)
    _day_controls(server)
    if server.admin_id != player.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, detail="Only the admin can start the next day"
        )
    day_flow.advance(session, server, days.current_day(server))
    session.commit()
    session.refresh(server)
    return _today(session, server, seat)


@router.get("/{code}/challengers", response_model=list[ChallengerResponse])
def get_challengers(
    code: Code, player: CurrentPlayer, session: DbSession
) -> list[ChallengerResponse]:
    """The challengers you encountered, newest first: the ones you drew,
    fought against or boosted, with their decided fights and wins, and for
    the ones you drew, the stars they won to collect. Challengers aren't
    part of the gacha pool."""
    server, seat = running_game(session, code, player.id)
    # Chance picks the fighters left of yesterday's fights first.
    fights.complete_fights(session, server, days.current_day(server) - 1)
    return _challengers(session, server, seat)


def _challengers(
    session: Session, server: Server, seat: ServerSeat
) -> list[ChallengerResponse]:
    records = fights.encountered_challengers(session, server, seat)
    rewards = {r.challenger.id: stars.challenger_stars(r, seat.id) for r in records}
    collected = stars.granted(
        session, seat.id, [reason for won in rewards.values() for reason, _ in won]
    )
    return [
        ChallengerResponse(
            character=character_response(record.challenger),
            fights=record.fights,
            wins=record.wins,
            stars_to_collect=sum(
                n for reason, n in rewards[record.challenger.id] if reason not in collected
            ),
            stars_collected=sum(
                n for reason, n in rewards[record.challenger.id] if reason in collected
            ),
        )
        for record in records
    ]


@router.post(
    "/{code}/challengers/{challenger_id}/stars",
    response_model=list[ChallengerResponse],
)
def collect_challenger_stars(
    code: Code, challenger_id: uuid.UUID, player: CurrentPlayer, session: DbSession
) -> list[ChallengerResponse]:
    """Collects the stars your challenger won in its fights: its stars in
    each, once that fight's day is over. Returns the challengers you
    encountered. Collecting again changes nothing."""
    server, seat = running_game(session, code, player.id)
    fights.complete_fights(session, server, days.current_day(server) - 1)
    record = next(
        (
            r
            for r in fights.encountered_challengers(session, server, seat)
            if r.challenger.id == challenger_id
        ),
        None,
    )
    if record is None or record.challenger.artist_seat_id != seat.id:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, detail="You didn't draw this challenger"
        )
    rewards = stars.challenger_stars(record, seat.id)
    collected = stars.granted(session, seat.id, [reason for reason, _ in rewards])
    for reason, n in rewards:
        if reason not in collected:
            session.add(stars.grant(seat.id, reason, n))
    try:
        session.commit()
    except IntegrityError:
        session.rollback()  # Collected at the same time elsewhere.
    return _challengers(session, server, seat)


@router.get("/{code}/ranking", response_model=RankingResponse | None)
def get_ranking(
    code: Code, player: CurrentPlayer, session: DbSession
) -> RankingResponse | None:
    """The latest finished week's challengers, most stars first; the first
    joined the gacha pool as a hero. Null before the first week is over.

    In speed mode, all of the session's challengers once it's over."""
    server, _ = running_game(session, code, player.id)
    if speed.is_speed(server):
        if not speed.clock(server).over:
            return None
        # The last day's boosts and fights nobody finished count too.
        last_day = SPEED_DAYS
        fights.complete_boosts(session, server, last_day)
        fights.complete_fights(session, server, last_day)
        ranked = finale.ranking(session, server, last_day + 1)
    else:
        finale.settle(session, server)
        week = finale.latest_finale(session, server)
        if week is None:
            return None
        last_day = week.day
        ranked = finale.ranking(session, server, week.day)
    return RankingResponse(
        day=last_day,
        challengers=[
            RankedChallenger(
                character=character_response(r.challenger),
                stars=r.stars,
                fights=r.fights,
                wins=r.wins,
            )
            for r in ranked
        ],
    )


@router.get("/{code}/win-rates", response_model=WinRatesResponse)
def get_win_rates(
    code: Code, player: CurrentPlayer, session: DbSession
) -> WinRatesResponse:
    """This week's win rates, from last week's fights: a player's characters
    get extra stars against another player's after winning most of their
    meetings, every fighter meeting the challenger once. Speed mode sessions
    have none."""
    server, _ = running_game(session, code, player.id)
    if speed.is_speed(server):
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="Speed mode sessions have no win rates"
        )
    day = days.current_day(server)
    fights.complete_fights(session, server, day - 1)
    fights.decide_fights(session, server)
    positions = {s.id: s.position for s in server.seats}
    first, last = win_rates.counted_week(server, day)
    return WinRatesResponse(
        from_day=first,
        to_day=last,
        min_fights=WIN_RATE_MIN_FIGHTS,
        win_rates=[
            WinRate(
                player_position=positions[r.player],
                against_position=positions[r.against],
                fights=r.fights,
                wins=r.wins,
                extra_stars=r.extra_stars,
            )
            for r in win_rates.records(session, server, day)
        ],
    )


@router.get("/{code}/fights", response_model=list[FightDay])
def get_fight_days(
    code: Code, player: CurrentPlayer, session: DbSession
) -> list[FightDay]:
    """The days before today with fights to replay, newest first."""
    server, _ = running_game(session, code, player.id)
    today = days.current_day(server)
    fights.complete_fights(session, server, today - 1)
    seat_ids = [s.id for s in server.seats]
    fought = session.scalars(
        select(Fight.day)
        .where(Fight.owner_seat_id.in_(seat_ids), Fight.day < today)
        .distinct()
        .order_by(Fight.day.desc())
    ).all()
    return [FightDay(day=day, date=days.calendar_date(server, day)) for day in fought]


@router.get("/{code}/fights/{day}", response_model=list[FightResponse])
def get_fights_of_day(
    code: Code, day: int, player: CurrentPlayer, session: DbSession
) -> list[FightResponse]:
    """Every fight of a day before today, in roster order of the fighters'
    players, to replay."""
    server, _ = running_game(session, code, player.id)
    if day >= days.current_day(server):
        raise HTTPException(
            status.HTTP_409_CONFLICT, detail="Only the fights of past days replay"
        )
    fights.complete_fights(session, server, day)
    fights.decide_fights(session, server)
    seats = sorted(server.seats, key=lambda s: s.position)
    return [
        _fight_response(session, server, fight)
        for seat in seats
        if (fight := fights.fight_of(session, seat, day)) is not None
    ]
