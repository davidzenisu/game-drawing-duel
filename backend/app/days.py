"""The days of a running game: which day it is, and who writes and draws what.

Most choices are random but derived from the server, day and seat, so they
stay the same on every request without being stored beforehand. The prompt
hints are stored when first given out, as a server uses each one once only.
"""

import hashlib
import random
import uuid
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app import speed
from app.models import (
    ChallengerPrompt,
    Character,
    HintAssignment,
    Server,
    ServerSeat,
    ThemeHint,
)
from app.rules import SPEED_LAST_PROMPT_DAY, Theme, least_picked, theme_of_date

# Stands in if the author of a missing prompt got no hint ("NO PROMPT").
FALLBACK_TITLE = "The Mystery Challenger"


def _launch_date(server: Server) -> date:
    launched = server.launched_at
    if launched.tzinfo is None:  # SQLite drops the time zone.
        launched = launched.replace(tzinfo=UTC)
    return launched.astimezone(UTC).date()


def current_day(server: Server, now: datetime | None = None) -> int:
    """Day 1 is the launch day. Regular servers move on at midnight UTC,
    speed mode sessions on their timers or once everyone is done (past the
    last day, the session is over), test sessions when the admin or everyone
    ends the day."""
    if server.is_test:
        return server.test_day or 1
    if speed.is_speed(server):
        return speed.clock(server, now).day
    today = (now or datetime.now(UTC)).astimezone(UTC).date()
    return (today - _launch_date(server)).days + 1


def date_of_day(server: Server, day: int) -> date:
    """The calendar day (UTC) a day of the game falls on. Test sessions count
    on from their launch date as the days advance."""
    return _launch_date(server) + timedelta(days=day - 1)


def calendar_date(server: Server, day: int) -> date:
    """The calendar day (UTC) a day of the game was played on: a speed mode
    session plays all of its days on its launch date."""
    if speed.is_speed(server):
        return _launch_date(server)
    return date_of_day(server, day)


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


def shuffled(server: Server, prompt_day: int) -> bool:
    """Whether the challengers of the prompts written on `prompt_day` are
    handed round at random: who draws each prompt, then who boosts and who
    fights the challenger. Servers that were running when that came in keep
    the roster order for what had started (`Server.shuffled_from_day`);
    sessions launched since shuffle from day 1."""
    return (
        server.shuffled_from_day is not None and prompt_day >= server.shuffled_from_day
    )


def _drawers(
    session: Session,
    server: Server,
    prompt_day: int,
    written: dict[uuid.UUID, uuid.UUID] | None = None,
) -> dict[uuid.UUID, ServerSeat]:
    """Who draws the prompt each player wrote, or the premade one standing in,
    on `prompt_day`, by the author's seat: a fresh random hand-out per day
    (`shuffled`), never their own prompt and, where possible, never one of
    themselves. Before, the next player in the roster drew it. The same
    every time it's asked, once the day's prompts are in. `written` is the
    day's prompts (their subject by author), if already loaded."""
    seats = active_seats(server)
    if len(seats) < 2:
        return {}
    if not shuffled(server, prompt_day):
        return {a.id: seats[(i + 1) % len(seats)] for i, a in enumerate(seats)}
    if written is None:
        written = {
            p.author_seat_id: p.subject_seat_id
            for p in session.scalars(
                select(ChallengerPrompt).where(
                    ChallengerPrompt.day == prompt_day,
                    ChallengerPrompt.author_seat_id.in_([s.id for s in seats]),
                )
            )
        }
    subjects = {
        a.id: written.get(a.id) or premade_subject(server, prompt_day, a).id
        for a in seats
    }
    rng = random.Random(f"{server.id}:{prompt_day}:drawers")
    best: list[ServerSeat] | None = None
    best_clashes = len(seats) + 1
    # Random orders until one gives nobody their own prompt or a prompt of
    # themselves; with everyone's prompt of the same player there's none,
    # so the fewest drawers of themselves.
    for _ in range(500):
        order = seats[:]
        rng.shuffle(order)
        if any(d.id == a.id for a, d in zip(seats, order, strict=True)):
            continue
        clashes = sum(d.id == subjects[a.id] for a, d in zip(seats, order, strict=True))
        if clashes < best_clashes:
            best, best_clashes = order, clashes
            if clashes == 0:
                break
    if best is None:  # No derangement found: practically impossible.
        best = seats[1:] + seats[:1]
    return {a.id: d for a, d in zip(seats, best, strict=True)}


def written_prompt_authors(
    session: Session, server: Server, first: int, last: int
) -> dict[tuple[uuid.UUID, int], uuid.UUID]:
    """Who wrote the prompt each challenger drawn from day `first` to day
    `last` came from, by (artist seat, day drawn): only the prompts a player
    wrote, not the premade ones standing in. In one query, whatever the days
    (`prompt_to_draw` asks one prompt at a time)."""
    seats = active_seats(server)
    written: dict[int, dict[uuid.UUID, uuid.UUID]] = defaultdict(dict)
    for author_id, day, subject_id in session.execute(
        select(
            ChallengerPrompt.author_seat_id,
            ChallengerPrompt.day,
            ChallengerPrompt.subject_seat_id,
        ).where(
            ChallengerPrompt.author_seat_id.in_([s.id for s in seats]),
            ChallengerPrompt.day >= first - 1,
            ChallengerPrompt.day <= last - 1,
        )
    ):
        written[day][author_id] = subject_id
    authors: dict[tuple[uuid.UUID, int], uuid.UUID] = {}
    for prompt_day, prompts in written.items():
        if prompt_day < 1 or not prompts_on(server, prompt_day):
            continue
        for author_id, drawer in _drawers(session, server, prompt_day, prompts).items():
            if author_id in prompts:
                authors[(drawer.id, prompt_day + 1)] = author_id
    return authors


def author_for(
    session: Session, server: Server, prompt_day: int, drawer: ServerSeat
) -> ServerSeat | None:
    """Whose prompt of `prompt_day` `drawer` draws, see `_drawers`."""
    for author_id, d in _drawers(session, server, prompt_day).items():
        if d.id == drawer.id:
            return next(s for s in server.seats if s.id == author_id)
    return None


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


def prompts_on(server: Server, day: int) -> bool:
    """Whether challenger prompts are written on `day`: every day, but only
    the first days of a speed mode session."""
    return not speed.is_speed(server) or day <= SPEED_LAST_PROMPT_DAY


def draws_on(server: Server, day: int) -> bool:
    """Whether challengers are drawn on `day`: the day after a prompt day."""
    return day >= 2 and prompts_on(server, day - 1)


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


def week_picks(session: Session, server: Server, day: int) -> dict[uuid.UUID, int]:
    """How often the prompts of `day`'s week before `day` picked each seat
    of the roster: the ones players wrote, and the premade ones standing in
    for the players who wrote none."""
    first = max(week_start(server, day), 1)
    seats = active_seats(server)
    written = {
        (author_id, prompt_day): subject_id
        for author_id, prompt_day, subject_id in session.execute(
            select(
                ChallengerPrompt.author_seat_id,
                ChallengerPrompt.day,
                ChallengerPrompt.subject_seat_id,
            ).where(
                ChallengerPrompt.author_seat_id.in_([s.id for s in seats]),
                ChallengerPrompt.day >= first,
                ChallengerPrompt.day < day,
            )
        )
    }
    picks = {s.id: 0 for s in server.seats}
    for prompt_day in range(first, day):
        if not prompts_on(server, prompt_day):
            continue
        for author in seats:
            subject_id = written.get((author.id, prompt_day))
            if subject_id is None:
                subject_id = premade_subject(server, prompt_day, author).id
            picks[subject_id] += 1
    return picks


def least_picked_seats(session: Session, server: Server, day: int) -> set[uuid.UUID]:
    """The seats a prompt written on `day` earns `rules.STARS_FOR_LEAST_PICKED`
    for: the ones the week picked least so far (`rules.least_picked`), the
    whole roster counted, whether they joined or not. None on a week's first
    day, nor in speed mode, which has no weeks."""
    if speed.is_speed(server) or day <= week_start(server, day):
        return set()
    picks = week_picks(session, server, day)
    roster = sorted(server.seats, key=lambda s: s.position)
    return {roster[i].id for i in least_picked([picks[s.id] for s in roster])}


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
    """The prompt `drawer` draws on `day`: the one a player handed to them
    at random wrote the day before (see `_drawers`), or a premade one if
    they didn't. In speed mode, only the prompts of the days that have them
    are drawn."""
    if day <= 1 or not prompts_on(server, day - 1):
        return None
    author = author_for(session, server, day - 1, drawer)
    if author is None:
        return None
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


def drawn_challenger(session: Session, seat: ServerSeat, day: int) -> Character | None:
    """The challenger `seat` drew on `day`, if any."""
    return session.scalar(
        select(Character).where(
            Character.artist_seat_id == seat.id, Character.day == day
        )
    )
