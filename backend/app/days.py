"""The days of a running game: which day it is, and who writes and draws what.

Most choices are random but derived from the server, day and seat, so they
stay the same on every request without being stored beforehand. The prompt
hints are stored when first given out, as a server uses each one once only.
"""

import hashlib
import random
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.models import (
    ChallengerPrompt,
    HintAssignment,
    Server,
    ServerSeat,
    ThemeHint,
)
from app.rules import Theme, theme_of_date

# Stands in if the author of a missing prompt got no hint ("NO PROMPT").
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


def week_start(server: Server, day: int) -> int:
    """The first day of the game in `day`'s week. Weeks start on Monday (UTC),
    like the themes; the launch week may start before day 1."""
    return day - date_of_day(server, day).weekday()


# A challenger is fought three days after its prompt was written: it's drawn
# the day after, boosted the day after that, and fought the next day. It
# takes the theme of the day it's fought.
FIGHT_DAY_OFFSET = 3


def challenger_theme(server: Server, prompt_day: int) -> Theme:
    """The theme of a challenger whose prompt is written on `prompt_day`: the
    theme of the day it's fought, so a day shows the theme of the
    challengers fought on it."""
    return theme_of(server, prompt_day + FIGHT_DAY_OFFSET)


def _in_use(server: Server, day: int, theme: Theme, model) -> tuple:
    """Filters `model`'s rows (hints) to `theme`'s on `day`. Only rows created before the day began count, and retired ones
    until the end of the day they were retired, so adding or retiring rows
    never changes a day's picks."""
    day_start = datetime.combine(date_of_day(server, day), time(), tzinfo=UTC)
    return (
        model.theme == theme.value,
        model.created_at < day_start,
        or_(model.retired_at.is_(None), model.retired_at >= day_start),
    )


def hints_on(
    session: Session, server: Server, day: int, theme: Theme
) -> list[ThemeHint]:
    """`theme`'s hints in use on `day`."""
    return list(
        session.scalars(
            select(ThemeHint)
            .where(*_in_use(server, day, theme, ThemeHint))
            .order_by(ThemeHint.created_at, ThemeHint.id)
        )
    )


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


def _hint_assignments(
    session: Session, server: Server, day: int
) -> dict[uuid.UUID, HintAssignment]:
    return {
        a.seat_id: a
        for a in session.scalars(
            select(HintAssignment)
            .where(HintAssignment.server_id == server.id, HintAssignment.day == day)
            .options(selectinload(HintAssignment.hint))
        )
    }


def _assign_hints(session: Session, server: Server, day: int) -> None:
    """Gives every seat without one a hint of the challenger's theme for
    `day` that the server never used, in an order of the server's own, and
    none once they're used up. Commits."""
    assigned = _hint_assignments(session, server, day)
    used = set(
        session.scalars(
            select(HintAssignment.hint_id).where(
                HintAssignment.server_id == server.id,
                HintAssignment.hint_id.is_not(None),
            )
        )
    )
    theme = challenger_theme(server, day)
    unused = sorted(
        (hint for hint in hints_on(session, server, day, theme) if hint.id not in used),
        key=lambda hint: hashlib.sha256(f"{server.id}:{hint.id}".encode()).digest(),
    )
    try:
        with session.begin_nested():
            for seat in active_seats(server):
                if seat.id not in assigned:
                    hint = unused.pop(0) if unused else None
                    session.add(
                        HintAssignment(
                            server_id=server.id,
                            seat_id=seat.id,
                            day=day,
                            hint_id=hint.id if hint else None,
                        )
                    )
    except IntegrityError:
        pass  # Someone else assigned them at the same time.
    session.commit()


def assigned_hint(
    session: Session, server: Server, day: int, author: ServerSeat
) -> ThemeHint | None:
    """The hint `author` picks a person and writes a title for on `day`, of
    the challenger's theme. A server uses every hint once at most; once the
    theme's hints are used up, there's none."""
    assigned = _hint_assignments(session, server, day)
    if author.id not in assigned:
        _assign_hints(session, server, day)
        assigned = _hint_assignments(session, server, day)
    assignment = assigned.get(author.id)
    return assignment.hint if assignment else None


def prompt_hint(
    session: Session, server: Server, day: int, author: ServerSeat
) -> str | None:
    """The description of `author`'s hint on `day`, see `assigned_hint`."""
    hint = assigned_hint(session, server, day, author)
    return hint.text if hint else None


def can_be_subject(author: ServerSeat, subject: ServerSeat) -> bool:
    """Anyone of the roster but yourself, whether they joined or not."""
    return subject.server_id == author.server_id and subject.id != author.id


def premade_subject(server: Server, day: int, author: ServerSeat) -> ServerSeat:
    """The person of a premade prompt that stands in for `author`'s on `day`."""
    candidates = [s for s in server.seats if can_be_subject(author, s)]
    return _rng(server, day, author, "subject").choice(candidates)


@dataclass(frozen=True)
class PromptToDraw:
    author: ServerSeat
    subject: ServerSeat
    title: str
    theme: Theme
    # The description the author chose the person and wrote the title for.
    hint: str | None
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
            hint=written.hint,
            premade=False,
        )
    # The premade title of the hint the author got, with its description.
    hint = assigned_hint(session, server, day - 1, author)
    return PromptToDraw(
        author=author,
        subject=premade_subject(server, day - 1, author),
        title=hint.premade_title if hint else FALLBACK_TITLE,
        theme=challenger_theme(server, day - 1),
        hint=hint.text if hint else None,
        premade=True,
    )
