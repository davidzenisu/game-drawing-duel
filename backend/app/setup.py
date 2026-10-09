"""Turns the setup rules into assignments for the seats of a server."""

from app import rules
from app.models import Server, ServerSeat, SetupAssignment


def assign_setup(server: Server, artists: list[ServerSeat]) -> list[SetupAssignment]:
    """The setup assignments of `artists`, which must be seats of `server`.

    A regular server's setup involves every seat. A test session's involves
    only the seats that joined, so a player joining one late is assigned
    among everyone who joined until then.
    """
    if server.is_test:
        roster = [seat for seat in server.seats if seat.player_id is not None]
        assign = rules.test_assignments_for
    else:
        roster = list(server.seats)
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
