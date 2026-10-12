"""The days of a running game: which day it is, and who writes and draws what.

Every choice is random but derived from the server, day and seat, so it
stays the same on every request without being stored beforehand.
"""

import random
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ChallengerPrompt, PremadeTitle, Server, ServerSeat, ThemeHint
from app.rules import Theme, theme_of_date

# Stands in if the database has no premade title for a theme yet.
FALLBACK_TITLE = "The Mystery Challenger"


def _launch_date(server: Server) -> date:
    launched = server.launched_at
    if launched.tzinfo is None:  # SQLite drops the time zone.
        launched = launched.replace(tzinfo=UTC)
    return launched.astimezone(UTC).date()


def current_day(server: Server, now: datetime | None = None) -> int:
    """Day 1 is the launch day. Regular servers move on at midnight UTC,
    test sessions when the admin or everyone ends the day."""
    if server.is_test:
        return server.test_day or 1
    today = (now or datetime.now(UTC)).astimezone(UTC).date()
    return (today - _launch_date(server)).days + 1


def date_of_day(server: Server, day: int) -> date:
    """The calendar day (UTC) a day of the game falls on. Test sessions count
    on from their launch date as the days advance."""
    return _launch_date(server) + timedelta(days=day - 1)


def theme_of(server: Server, day: int) -> Theme:
    """The theme of a day of the game: the one of its weekday."""
    return theme_of_date(date_of_day(server, day))


def _pick(
    session: Session, server: Server, day: int, column, rng: random.Random
) -> str | None:
    """One of the theme's hints or premade titles (`column`) for `day`, or
    None if there are none. Only rows created before the day began count, so
    adding rows never changes a day's pick."""
    day_start = datetime.combine(date_of_day(server, day), time(), tzinfo=UTC)
    model = column.class_
    options = session.scalars(
        select(column)
        .where(model.theme == theme_of(server, day).value, model.created_at < day_start)
        .order_by(model.created_at, model.id)
    ).all()
    return rng.choice(options) if options else None


def active_seats(server: Server) -> list[ServerSeat]:
    """The players of a running game, in roster order."""
    return sorted(
        (s for s in server.seats if s.player_id is not None), key=lambda s: s.position
    )


def drawer_of(server: Server, author: ServerSeat) -> ServerSeat:
    """Who draws the prompt `author` writes: the next player."""
    seats = active_seats(server)
    return seats[(seats.index(author) + 1) % len(seats)]


def author_for(server: Server, drawer: ServerSeat) -> ServerSeat:
    """Whose prompt `drawer` draws: the previous player's."""
    seats = active_seats(server)
    return seats[(seats.index(drawer) - 1) % len(seats)]


def _rng(server: Server, day: int, seat: ServerSeat, purpose: str) -> random.Random:
    return random.Random(f"{server.id}:{day}:{seat.id}:{purpose}")


def prompt_hint(
    session: Session, server: Server, day: int, author: ServerSeat
) -> str | None:
    """An idea for the title `author` writes on `day`, one of the theme's."""
    return _pick(session, server, day, ThemeHint.text, _rng(server, day, author, "hint"))


def prompt_subject(server: Server, day: int, author: ServerSeat) -> ServerSeat:
    """The character `author` writes a prompt for on `day`: anyone of the
    roster but themselves and the player who draws it."""
    drawer = drawer_of(server, author)
    candidates = [s for s in server.seats if s.id not in {author.id, drawer.id}]
    return _rng(server, day, author, "subject").choice(candidates)


@dataclass(frozen=True)
class PromptToDraw:
    author: ServerSeat
    subject: ServerSeat
    title: str
    theme: Theme
    # Nobody wrote it: a premade title stands in.
    premade: bool


def prompt_to_draw(
    session: Session, server: Server, day: int, drawer: ServerSeat
) -> PromptToDraw | None:
    """The prompt `drawer` draws on `day`: the one the previous player wrote
    the day before, or a premade one if they didn't."""
    if day <= 1:
        return None
    author = author_for(server, drawer)
    written = session.scalar(
        select(ChallengerPrompt).where(
            ChallengerPrompt.author_seat_id == author.id,
            ChallengerPrompt.day == day - 1,
        )
    )
    seats = {s.id: s for s in server.seats}
    if written is not None:
        return PromptToDraw(
            author=author,
            subject=seats[written.subject_seat_id],
            title=written.title,
            theme=Theme(written.theme),
            premade=False,
        )
    rng = _rng(server, day - 1, author, "premade")
    title = _pick(session, server, day - 1, PremadeTitle.title, rng)
    return PromptToDraw(
        author=author,
        subject=prompt_subject(server, day - 1, author),
        title=title or FALLBACK_TITLE,
        theme=theme_of(server, day - 1),
        premade=True,
    )
