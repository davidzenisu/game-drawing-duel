"""Turns the setup rules into assignments for the seats of a server."""

import random
from collections import defaultdict
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import rules, speed
from app.models import Server, ServerSeat, SetupAssignment, SetupHint
from app.pulls import grant_launch_bonus


def assign_setup(server: Server, artists: list[ServerSeat]) -> list[SetupAssignment]:
    """The setup assignments of `artists`, which must be seats of `server`.

    In a regular server every seat draws; in speed mode every seat draws two
    characters; in a test session only the seats that joined do, but of
    randomly picked players of the whole roster.
    """
    roster = list(server.seats)
    if server.is_test:
        assign = rules.test_assignments_for
    elif speed.is_speed(server):
        assign = rules.speed_assignments_for
    else:
        assign = rules.assignments_for
    assignments = []
    for artist in artists:
        by_prompt: dict[rules.SetupPrompt, SetupAssignment] = {}
        for planned in assign(len(roster), roster.index(artist)):
            based_on = planned.prompt.based_on
            by_prompt[planned.prompt] = SetupAssignment(
                artist=artist,
                subject=roster[planned.subject],
                prompt=planned.prompt.value,
                based_on=by_prompt[based_on] if based_on else None,
            )
        assignments.extend(by_prompt.values())
    return assignments


def give_hints(
    session: Session,
    assignments: list[SetupAssignment],
    rng: random.Random | None = None,
) -> None:
    """Gives every assignment a random starter prompt of its type that isn't
    retired, without repeats within the server until a type's run out; an
    assignment gets none if its type has none."""
    rng = rng or random.SystemRandom()
    hints: dict[str, list[SetupHint]] = defaultdict(list)
    for hint in session.scalars(
        select(SetupHint)
        .where(SetupHint.retired_at.is_(None))
        .order_by(SetupHint.created_at, SetupHint.id)
    ):
        hints[hint.prompt].append(hint)
    left: dict[str, list[SetupHint]] = defaultdict(list)
    for assignment in assignments:
        if not hints[assignment.prompt]:
            continue
        if not left[assignment.prompt]:
            left[assignment.prompt] = rng.sample(
                hints[assignment.prompt], len(hints[assignment.prompt])
            )
        assignment.hint = left[assignment.prompt].pop()


def launch(session: Session, server: Server, at: datetime | None = None) -> None:
    """Launches the game: day 1 starts, `at` or now, and every player gets
    the launch bonus. The caller commits."""
    server.launched_at = at or func.now()
    if server.is_test:
        server.test_day = 1
    grant_launch_bonus(session, [s for s in server.seats if s.player_id is not None])


def launch_if_due(session: Session, server: Server) -> None:
    """Launches a speed mode setup once its time is up, with the drawings
    made so far: the missing ones are left out. Commits."""
    if server.launched_at is not None or not speed.setup_over(server):
        return
    # Requests at the same time wait for each other; one launches.
    session.scalar(select(Server.id).where(Server.id == server.id).with_for_update())
    session.refresh(server)
    if server.launched_at is None:
        launch(session, server, at=speed.setup_ends_at(server))
    session.commit()
    session.refresh(server)
