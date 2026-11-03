"""Everything played on a server, for deleting it all at once."""

import uuid

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.models import (
    Boost,
    ChallengerPrompt,
    Character,
    DayEnd,
    Fight,
    Fighter,
    HintAssignment,
    Hurry,
    Pull,
    PullGrant,
    Server,
    SetupAssignment,
    Upgrade,
)


def delete_game_data(session: Session, server: Server) -> list[uuid.UUID]:
    """Deletes everything played on `server` but the server and its seats;
    returns the ids of the deleted characters, whose drawings to delete."""
    seat_ids = [s.id for s in server.seats]
    character_ids = list(
        session.scalars(select(Character.id).where(Character.server_id == server.id))
    )
    fight_ids = select(Fight.id).where(Fight.owner_seat_id.in_(seat_ids))
    for statement in (
        delete(Boost).where(Boost.booster_seat_id.in_(seat_ids)),
        delete(Fighter).where(Fighter.fight_id.in_(fight_ids)),
        delete(Fight).where(Fight.owner_seat_id.in_(seat_ids)),
        delete(Upgrade).where(Upgrade.seat_id.in_(seat_ids)),
        delete(Pull).where(Pull.seat_id.in_(seat_ids)),
        delete(PullGrant).where(PullGrant.seat_id.in_(seat_ids)),
        delete(Hurry).where(Hurry.sender_seat_id.in_(seat_ids)),
        delete(DayEnd).where(DayEnd.seat_id.in_(seat_ids)),
        delete(HintAssignment).where(HintAssignment.server_id == server.id),
        delete(ChallengerPrompt).where(ChallengerPrompt.author_seat_id.in_(seat_ids)),
        delete(Character).where(Character.server_id == server.id),
        delete(SetupAssignment).where(SetupAssignment.artist_seat_id.in_(seat_ids)),
    ):
        session.execute(statement)
    return character_ids
