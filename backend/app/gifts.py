"""Pulls and stars an admin gives players outside the regular rewards
(`Gift`), or just a message, and their delivery: each recipient's seat gets
one to accept, and its pulls and stars only count once accepted. Gifts don't
expire."""

import uuid

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import stars as star_ledger
from app.database import utc_now
from app.models import Gift, GiftDelivery, PullGrant, Server, ServerSeat


class GiftError(Exception):
    pass


def recipients(
    session: Session, server: Server | None, positions: list[int] | None
) -> list[ServerSeat]:
    """Who a gift goes to: every seat of every server that wasn't cancelled
    without a `server`, else every seat of `server`, or only those at
    `positions`. Seats nobody joined yet get it to accept once they do."""
    if server is None:
        return list(
            session.scalars(
                select(ServerSeat)
                .join(Server, Server.id == ServerSeat.server_id)
                .where(Server.cancelled_at.is_(None))
                .order_by(Server.created_at, ServerSeat.position)
            )
        )
    seats = sorted(server.seats, key=lambda s: s.position)
    if positions is None:
        return seats
    by_position = {s.position: s for s in seats}
    missing = sorted(set(positions) - set(by_position))
    if missing:
        raise GiftError(f"No player at position {missing[0]} on this server")
    if not positions:
        raise GiftError("Pick at least one player")
    return [by_position[p] for p in sorted(set(positions))]


def send(
    session: Session,
    sender_id: uuid.UUID | None,
    message: str,
    pulls: int,
    server: Server | None,
    positions: list[int] | None,
    stars: int = 0,
) -> tuple[Gift, int]:
    """Sends a gift and returns it with its number of recipients. Commits."""
    seats = recipients(session, server, positions)
    if not seats:
        raise GiftError("Nobody to send it to")
    gift = Gift(
        message=message,
        pulls=pulls,
        stars=stars,
        sender_id=sender_id,
        server_id=server.id if server else None,
        deliveries=[GiftDelivery(seat_id=seat.id) for seat in seats],
    )
    session.add(gift)
    session.commit()
    return gift, len(seats)


def pending(session: Session, seat: ServerSeat) -> list[Gift]:
    """The gifts for `seat` that wait to be accepted, oldest first."""
    return list(
        session.scalars(
            select(Gift)
            .join(GiftDelivery, GiftDelivery.gift_id == Gift.id)
            .where(GiftDelivery.seat_id == seat.id, GiftDelivery.claimed_at.is_(None))
            .order_by(Gift.sent_at, Gift.id)
        )
    )


def accept(session: Session, seat: ServerSeat, gift_id: uuid.UUID) -> None:
    """Accepts a gift for `seat`: its pulls and stars now count. Accepting it
    again, or on two devices at once, gives them only once. Commits."""
    delivery = session.scalar(
        select(GiftDelivery).where(
            GiftDelivery.gift_id == gift_id, GiftDelivery.seat_id == seat.id
        )
    )
    if delivery is None:
        raise GiftError("No such gift for you")
    claimed = session.execute(
        update(GiftDelivery)
        .where(GiftDelivery.id == delivery.id, GiftDelivery.claimed_at.is_(None))
        .values(claimed_at=utc_now())
    )
    if claimed.rowcount == 0:
        session.rollback()
        return  # Accepted already.
    session.add_all(
        PullGrant(seat_id=seat.id, reason=f"gift:{gift_id}:{n}")
        for n in range(1, delivery.gift.pulls + 1)
    )
    if delivery.gift.stars:
        session.add(star_ledger.grant(seat.id, f"gift:{gift_id}", delivery.gift.stars))
    try:
        session.commit()
    except IntegrityError:
        session.rollback()  # Accepted at the same time elsewhere.
