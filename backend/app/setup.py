"""Turns the setup rules into assignments for the seats of a server."""

import random
from collections import defaultdict

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import rules
from app.models import Server, ServerSeat, SetupAssignment, SetupHint


def assign_setup(server: Server, artists: list[ServerSeat]) -> list[SetupAssignment]:
    """The setup assignments of `artists`, which must be seats of `server`.

    In a regular server every seat draws; in a test session only the seats
    that joined do, but of randomly picked players of the whole roster.
    """
    roster = list(server.seats)
    assign = rules.test_assignments_for if server.is_test else rules.assignments_for
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
