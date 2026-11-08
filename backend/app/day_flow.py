"""Moving test sessions and speed mode sessions on to the next day, before
midnight UTC: once the admin says so, once everyone ended the day, or, in
speed mode, as soon as everyone did everything there is to do."""

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app import days, fights, pulls, speed
from app.models import ChallengerPrompt, DayEnd, Server, ServerSeat
from app.rules import BOOST_STARS


def advance(session: Session, server: Server, day: int) -> None:
    """Moves a test session or speed mode session from `day` to the next,
    once."""
    if speed.is_speed(server):
        if days.current_day(server) == day and not speed.clock(server).over:
            speed.start_next_day(server, day)
        return
    session.execute(
        update(Server)
        .where(Server.id == server.id, Server.test_day == day)
        .values(test_day=day + 1)
    )


def seat_done(session: Session, server: Server, day: int, seat: ServerSeat) -> bool:
    """Whether `seat` did everything there is to do on `day`, or ended it."""
    if session.scalar(
        select(DayEnd.id).where(DayEnd.seat_id == seat.id, DayEnd.day == day)
    ):
        return True
    if days.prompts_on(server, day) and not session.scalar(
        select(ChallengerPrompt.id).where(
            ChallengerPrompt.author_seat_id == seat.id, ChallengerPrompt.day == day
        )
    ):
        return False
    if (
        days.prompt_to_draw(session, server, day, seat) is not None
        and days.drawn_challenger(session, seat, day) is None
    ):
        return False
    if (
        not fights.missed_drawing(session, server, day, seat)
        and fights.boost_targets(session, server, day, seat)
        and sum(fights.given_boosts(session, seat, day).values()) < BOOST_STARS
    ):
        return False
    can_fight = set(pulls.copies(session, seat)) - fights.resting(
        session, server, seat, day
    )
    return not (
        fights.fight_challenger(session, server, day, seat) is not None
        and fights.fight_of(session, seat, day) is None
        and can_fight
    )


def end_speed_day_if_done(session: Session, server: Server) -> None:
    """In speed mode, starts the next day as soon as everyone is done with
    today. Commits."""
    if not speed.is_speed(server):
        return
    # Players finishing at once wait for each other here, so the last one
    # sees everyone else's and moves the day on.
    session.scalar(select(Server.id).where(Server.id == server.id).with_for_update())
    session.refresh(server)
    day = days.current_day(server)
    if not speed.clock(server).over and all(
        seat_done(session, server, day, s) for s in days.active_seats(server)
    ):
        advance(session, server, day)
    session.commit()
    session.refresh(server)


def end_day(session: Session, server: Server, seat: ServerSeat) -> None:
    """`seat` is done for today; once everyone is, the next day starts.
    Commits."""
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
    if speed.is_speed(server):
        session.commit()
        end_speed_day_if_done(session, server)
        return
    ended = set(
        session.scalars(
            select(DayEnd.seat_id).where(
                DayEnd.day == day,
                DayEnd.seat_id.in_([s.id for s in server.seats]),
            )
        )
    )
    if all(s.id in ended for s in days.active_seats(server)):
        advance(session, server, day)
    session.commit()
    session.refresh(server)
