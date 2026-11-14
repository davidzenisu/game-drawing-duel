"""Your achievements in a running game and their rewards, see
`app.achievements`."""

from fastapi import APIRouter, HTTPException, status
from sqlalchemy.orm import Session

from app import achievements
from app.auth import CurrentPlayer
from app.deps import Code, DbSession, running_game
from app.models import Server, ServerSeat
from app.schemas import AchievementResponse

router = APIRouter(prefix="/servers", tags=["achievements"])


def _achievements(
    session: Session, server: Server, seat: ServerSeat
) -> list[AchievementResponse]:
    return [
        AchievementResponse(
            key=a.key,
            kind=a.kind,
            player_position=a.position,
            rarity=a.rarity.value if a.rarity else None,
            goal=a.goal,
            progress=a.progress,
            stars=a.stars,
            done=a.done,
            collected=a.collected,
        )
        for a in achievements.of(session, server, seat)
    ]


@router.get("/{code}/achievements", response_model=list[AchievementResponse])
def get_achievements(
    code: Code, player: CurrentPlayer, session: DbSession
) -> list[AchievementResponse]:
    """Your achievements, with your progress and whether you collected
    their stars."""
    server, seat = running_game(session, code, player.id)
    return _achievements(session, server, seat)


@router.post(
    "/{code}/achievements/{key}/collect", response_model=list[AchievementResponse]
)
def collect_achievement(
    code: Code, key: str, player: CurrentPlayer, session: DbSession
) -> list[AchievementResponse]:
    """Collects the stars of an achievement you reached. Returns your
    achievements. Collecting again changes nothing."""
    server, seat = running_game(session, code, player.id)
    try:
        achievements.collect(session, server, seat, key)
    except achievements.CantCollect as error:
        raise HTTPException(status.HTTP_409_CONFLICT, detail=str(error)) from error
    return _achievements(session, server, seat)
