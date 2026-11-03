"""Responses built from models that several routers send."""

from typing import Literal

from app import speed
from app.models import Character, Player, Server
from app.schemas import CharacterResponse, SeatResponse, ServerResponse


def character_response(character: Character) -> CharacterResponse:
    return CharacterResponse(
        id=character.id,
        title=character.title,
        rarity=character.rarity,
        prompt=character.prompt,
        artist_position=character.artist.position,
        subject_position=character.subject.position,
        day=character.day,
        theme=character.theme,
    )


def phase(
    server: Server,
) -> Literal["lobby", "setup", "running", "finished", "cancelled"]:
    if server.cancelled_at is not None:
        return "cancelled"
    if server.launched_at is not None:
        if speed.is_speed(server) and speed.clock(server).over:
            return "finished"
        return "running"
    return "lobby" if server.setup_started_at is None else "setup"


def server_response(server: Server, player: Player) -> ServerResponse:
    your_seat = next((s for s in server.seats if s.player_id == player.id), None)
    return ServerResponse(
        code=server.code,
        created_at=server.created_at,
        mode=server.mode,
        is_test=server.is_test,
        is_admin=server.admin_id == player.id,
        phase=phase(server),
        cancelled_by=server.cancelled_by,
        setup_ends_at=speed.setup_ends_at(server),
        your_position=your_seat.position if your_seat else None,
        seats=[
            SeatResponse(
                position=s.position,
                name=s.name,
                joined=s.player_id is not None,
                setup_done=s.setup_done_at is not None,
            )
            for s in server.seats
        ],
    )
