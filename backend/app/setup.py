"""Turns the setup rules into assignments for the seats of a server."""

from app import rules
from app.models import Server, ServerSeat, SetupAssignment


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
