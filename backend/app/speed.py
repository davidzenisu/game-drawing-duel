"""Speed mode: a one-off session of about 20 minutes, on timers.

The setup lasts `rules.SPEED_SETUP_SECONDS`; it launches once everyone is
done or the time is up. Then days 1 to `rules.SPEED_DAYS` follow back to
back, each on its own timer (`rules.SPEED_DAY_SECONDS`). A day ends early
once everyone is done with it: the next one starts right away and is stored
on the server (`speed_day`, `speed_day_started_at`), and the days after run
on their timers from there. After the last day, the session is over.
"""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from app.models import Server
from app.rules import SPEED_DAY_SECONDS, SPEED_DAYS, SPEED_SETUP_SECONDS

SPEED = "speed"


def is_speed(server: Server) -> bool:
    return server.mode == SPEED


def _aware(moment: datetime) -> datetime:
    # SQLite drops the time zone.
    return moment if moment.tzinfo is not None else moment.replace(tzinfo=UTC)


def setup_ends_at(server: Server) -> datetime | None:
    """When a speed mode setup launches at the latest."""
    if not is_speed(server) or server.setup_started_at is None:
        return None
    return _aware(server.setup_started_at) + timedelta(seconds=SPEED_SETUP_SECONDS)


def setup_over(server: Server, now: datetime | None = None) -> bool:
    ends = setup_ends_at(server)
    return ends is not None and (now or datetime.now(UTC)) >= ends


@dataclass(frozen=True)
class Clock:
    # The current day, or `SPEED_DAYS + 1` once the session is over.
    day: int
    # When the current day ends, or None once the session is over.
    ends_at: datetime | None

    @property
    def over(self) -> bool:
        return self.day > SPEED_DAYS


def clock(server: Server, now: datetime | None = None) -> Clock:
    """Where a launched speed mode session stands."""
    now = now or datetime.now(UTC)
    day = server.speed_day or 1
    started = _aware(server.speed_day_started_at or server.launched_at)
    while day <= SPEED_DAYS:
        ends = started + timedelta(seconds=SPEED_DAY_SECONDS[day - 1])
        if now < ends:
            return Clock(day, ends)
        day += 1
        started = ends
    return Clock(SPEED_DAYS + 1, None)


def start_next_day(server: Server, day: int, now: datetime | None = None) -> None:
    """Ends `day` early: the next one starts now. The caller commits."""
    server.speed_day = day + 1
    server.speed_day_started_at = now or datetime.now(UTC)
