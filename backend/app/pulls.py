"""Awarding and spending gacha pulls."""

import random
import uuid
from collections import defaultdict
from dataclasses import dataclass

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app import stars
from app.gacha import LAUNCH_BONUS, Banner, GachaState, pick_character, pull_rarity
from app.models import (
    ArenaHero,
    Character,
    Pull,
    PullGrant,
    ServerSeat,
    WeeklyHero,
)
from app.rules import Rarity


def in_pool():
    """The gacha pool holds the setup drawings, the weekly heroes (the
    challengers a finale crowned, `app.finale`) and the Arena winners
    (`app.arena`); other challengers stay out."""
    return or_(
        Character.assignment_id.is_not(None),
        Character.id.in_(
            select(WeeklyHero.character_id).where(WeeklyHero.character_id.is_not(None))
        ),
        Character.id.in_(
            select(ArenaHero.character_id).where(ArenaHero.character_id.is_not(None))
        ),
    )


def rate_up(session: Session, server_id: uuid.UUID) -> set[uuid.UUID]:
    """This week's rate-up characters: the heroes of the latest finale
    (`app.finale`). They rotate every Monday with the finale; a week
    without heroes has none."""
    day = session.scalar(
        select(func.max(WeeklyHero.day)).where(WeeklyHero.server_id == server_id)
    )
    return set(
        session.scalars(
            select(WeeklyHero.character_id).where(
                WeeklyHero.server_id == server_id,
                WeeklyHero.day == day,
                WeeklyHero.character_id.is_not(None),
            )
        )
    )


def grant_launch_bonus(session: Session, seats: list[ServerSeat]) -> None:
    """The pulls every player receives when the game launches."""
    session.add_all(
        PullGrant(seat_id=seat.id, reason=f"launch-bonus:{n}")
        for seat in seats
        for n in range(1, LAUNCH_BONUS + 1)
    )


def _unspent_grants(seat_id: uuid.UUID):
    return (
        select(PullGrant)
        .outerjoin(Pull, Pull.grant_id == PullGrant.id)
        .where(PullGrant.seat_id == seat_id, Pull.id.is_(None))
    )


def tickets(session: Session, seat_id: uuid.UUID) -> int:
    """How many pulls the seat has left."""
    return session.scalar(
        select(func.count()).select_from(_unspent_grants(seat_id).subquery())
    )


def gacha_state(session: Session, seat_id: uuid.UUID) -> GachaState:
    return GachaState.after(_pulled(session, seat_id))


def _pulled(session: Session, seat_id: uuid.UUID) -> list[tuple[Banner, Rarity]]:
    """The banners and rarities the seat pulled, in order."""
    pulled = session.execute(
        select(Pull.banner, Pull.rarity)
        .where(Pull.seat_id == seat_id)
        .order_by(Pull.number)
    )
    return [(Banner(banner), Rarity(rarity)) for banner, rarity in pulled]


def copies(session: Session, seat: ServerSeat) -> dict[uuid.UUID, int]:
    """How many copies of each character the seat owns: the ones they drew
    during the setup (in speed mode only the basic one), plus every pull."""
    owned: dict[uuid.UUID, int] = defaultdict(int)
    drawn = select(Character.id).where(
        Character.artist_seat_id == seat.id, Character.assignment_id.is_not(None)
    )
    if seat.server.mode == "speed":
        drawn = drawn.where(Character.rarity == Rarity.BASIC.value)
    for character_id in session.scalars(drawn):
        owned[character_id] += 1
    for character_id in session.scalars(
        select(Pull.character_id).where(Pull.seat_id == seat.id)
    ):
        owned[character_id] += 1
    return owned


def lock(session: Session, seat_id: uuid.UUID) -> None:
    """Locks the seat until the transaction ends, so the same player
    pulling or buying pulls twice at once waits for the first."""
    session.scalar(
        select(ServerSeat.id).where(ServerSeat.id == seat_id).with_for_update()
    )


def arena_rate_up(session: Session, server_id: uuid.UUID) -> set[uuid.UUID]:
    """The Arena banner's rate-up characters: the winners of the latest
    Arena (`app.arena`). They rotate every Monday as an Arena is decided; an
    Arena without winners has none."""
    week = session.scalar(
        select(func.max(ArenaHero.week)).where(ArenaHero.server_id == server_id)
    )
    return set(
        session.scalars(
            select(ArenaHero.character_id).where(
                ArenaHero.server_id == server_id,
                ArenaHero.week == week,
                ArenaHero.character_id.is_not(None),
            )
        )
    )


def featured(session: Session, server_id: uuid.UUID, banner: Banner) -> set[uuid.UUID]:
    """The rate-up characters of `banner`: none on the standard one."""
    match banner:
        case Banner.WEEKLY:
            return rate_up(session, server_id)
        case Banner.ARENA:
            return arena_rate_up(session, server_id)
    return set()


class NotEnoughPulls(Exception):
    pass


class BannerClosed(Exception):
    """The weekly banner opens with the first finale, the Arena banner with
    the first Arena's winners."""


@dataclass(frozen=True)
class Outcome:
    character: Character
    is_new: bool
    copies: int


def pull(
    session: Session,
    seat: ServerSeat,
    count: int,
    banner: Banner = Banner.STANDARD,
    rng: random.Random | None = None,
    top_up: bool = False,
) -> list[Outcome]:
    """Spends `count` of the seat's grants on characters of `banner`: both
    pull from the whole pool (`in_pool`), the weekly one with this week's
    rate-up. With `top_up`, stars buy the pulls the seat is short of first
    (`stars.buy_pulls`, which raises `stars.CantBuyPull` without enough).

    Locks the seat, so the same player pulling twice at once waits instead of
    spending the same grants (or stars); the caller commits, or rolls back
    on an error.
    """
    rng = rng or random.SystemRandom()
    lock(session, seat.id)
    if top_up:
        stars.buy_pulls(session, seat.id, count - tickets(session, seat.id))
    grants = session.scalars(
        _unspent_grants(seat.id).order_by(PullGrant.granted_at).limit(count)
    ).all()
    if len(grants) < count:
        raise NotEnoughPulls
    rate_up_ids = featured(session, seat.server_id, banner)
    if banner is not Banner.STANDARD and not rate_up_ids:
        raise BannerClosed
    by_rarity: dict[Rarity, list[Character]] = defaultdict(list)
    for character in session.scalars(
        select(Character)
        .where(
            Character.server_id == seat.server_id,
            in_pool(),
        )
        .order_by(Character.id)
    ):
        by_rarity[Rarity(character.rarity)].append(character)
    pulled = _pulled(session, seat.id)
    owned = copies(session, seat)
    outcomes = []
    for grant in grants:
        rarity = pull_rarity(GachaState.after(pulled), banner, set(by_rarity), rng)
        character = pick_character(
            by_rarity[rarity], lambda c: c.id in rate_up_ids, rng
        )
        pulled.append((banner, rarity))
        owned[character.id] += 1
        session.add(
            Pull(
                seat_id=seat.id,
                grant_id=grant.id,
                number=len(pulled),
                character_id=character.id,
                rarity=rarity.value,
                banner=banner.value,
            )
        )
        outcomes.append(
            Outcome(
                character, is_new=owned[character.id] == 1, copies=owned[character.id]
            )
        )
    return outcomes
