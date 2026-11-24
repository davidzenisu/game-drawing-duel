"""The Arena: every player votes on matchups of two challengers, and the
Arena's top 3 by everyone's votes become Arena winners, for the Arena banner.

Week X's challengers are drawn, boosted and fought in week X (they count for
the week of their fight, like in the finale). Once week X is over, its
finale crowns its weekly heroes; the Arena of week X opens with all the
others, and everyone votes on it through week X+1. Once week X+1 is over,
the Arena's top 3 are crowned Arena winners and join the gacha pool, with the
finale's rarities by place; the other challengers leave the Arena. So the
Arena only ever holds a past week's challengers, never the present one's,
and the first one opens in a server's second week.

A player never gets a matchup with a drawing of their own, and votes on each
pair once: for one of them, or a draw ("can't decide"). A day's first
`rules.ARENA_PACK` votes earn `rules.ARENA_PACK_STARS` stars; voting goes on
after them, unrewarded, up to the day's cap (`rules.arena_daily_cap`): as
many as they like, as long as a pack's pairs stay for every day left. Matchups are picked by the fewest
votes first, then balancing the pairs of players the challengers portray,
then by close ratings. The ratings (`rules.arena_ratings`) are computed from
all of the Arena's votes at once and stay secret until it's decided. Speed
mode sessions have no weeks, so no Arena.
"""

import itertools
import random
import uuid
from collections import Counter
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app import days, finale, rules, speed, stars
from app.models import ArenaHero, ArenaVote, Character, Server, ServerSeat, WeeklyHero

# An Arena is voted on for the 7 days of the week after its challengers'.
DAYS = 7


def open_week(server: Server, day: int) -> int | None:
    """The Arena open on `day`: the last day of the week before (its
    challengers' week); None in the first week and in speed mode."""
    if speed.is_speed(server):
        return None
    week = days.week_start(server, day) - 1
    return week if week >= finale.finale_day(server, 1) else None


def ends_on(week: int) -> int:
    """The last day to vote in the Arena of `week`."""
    return week + DAYS


def challengers(
    session: Session, server: Server, week: int, *, ranked: bool = True
) -> list[Character]:
    """The Arena of `week`'s challengers: the ones fought that week, but its
    weekly heroes, in the order of their week's ranking, or in no particular
    order without `ranked` (cheaper). Its finale must be decided
    (`finale.settle`)."""
    heroes = finale.heroes_of(session, server, week)
    if not ranked:
        return [
            c
            for c in session.scalars(
                select(Character)
                .where(
                    Character.server_id == server.id,
                    Character.assignment_id.is_(None),
                    Character.day >= week - 6 - finale.FIGHT_AFTER_DRAWING,
                    Character.day <= week - finale.FIGHT_AFTER_DRAWING,
                )
                .order_by(Character.created_at, Character.id)
            )
            if c.id not in heroes
        ]
    return [
        r.challenger
        for r in finale.ranking(session, server, week)
        if r.challenger.id not in heroes
    ]


def _votes(session: Session, server: Server, week: int) -> list[ArenaVote]:
    return list(
        session.scalars(
            select(ArenaVote).where(
                ArenaVote.server_id == server.id, ArenaVote.week == week
            )
        )
    )


def _pair(a: uuid.UUID, b: uuid.UUID) -> tuple[uuid.UUID, uuid.UUID]:
    """A pair in its fixed order."""
    return (a, b) if str(a) < str(b) else (b, a)


@dataclass(frozen=True)
class Standing:
    challenger: Character
    rating: float
    # Its score in its matchups (a draw counts a half), and how many.
    score: float
    matchups: int


def standings(entries: list[Character], votes: list[ArenaVote]) -> list[Standing]:
    """The Arena's challengers best first (`rules.arena_order`), from
    `entries` in the order of their week's ranking."""
    index = {c.id: i for i, c in enumerate(entries)}
    matchups = []
    for vote in votes:
        if vote.first_id not in index or vote.second_id not in index:
            continue
        i, j = index[vote.first_id], index[vote.second_id]
        score = (
            0.5 if vote.winner_id is None else float(vote.winner_id == vote.first_id)
        )
        matchups.append((i, j, score))
    ratings = rules.arena_ratings(len(entries), matchups)
    scores = [0.0] * len(entries)
    counts = [0] * len(entries)
    for i, j, score in matchups:
        scores[i] += score
        scores[j] += 1 - score
        counts[i] += 1
        counts[j] += 1
    return [
        Standing(entries[i], ratings[i], scores[i], counts[i])
        for i in rules.arena_order(len(entries), matchups)
    ]


@dataclass(frozen=True)
class ArenaState:
    """A player's Arena on a day."""

    # The Arena open today; None when there's none (the first week, speed
    # mode).
    week: int | None = None
    # How many challengers it holds, and how many pairs you can vote on.
    challengers: int = 0
    # Your votes today, and the most you can cast today.
    votes_today: int = 0
    cap: int = 0
    # Whether today's pack earned its stars already.
    rewarded: bool = False
    # The next matchup to vote on, None at the cap or without pairs left.
    matchup: tuple[Character, Character] | None = None

    @property
    def pack(self) -> int:
        """The votes today's stars take: the pack, or the cap if lower."""
        return min(rules.ARENA_PACK, self.cap)


def _mine(votes: list[ArenaVote], seat: ServerSeat) -> list[ArenaVote]:
    return [v for v in votes if v.voter_seat_id == seat.id]


def _pairs(
    entries: list[Character], seat: ServerSeat
) -> list[tuple[Character, Character]]:
    """Every pair of the Arena `seat` can vote on: none with a drawing of
    their own."""
    theirs = [c for c in entries if c.artist_seat_id != seat.id]
    return list(itertools.combinations(theirs, 2))


def _matchup(
    server: Server,
    seat: ServerSeat,
    day: int,
    entries: list[Character],
    votes: list[ArenaVote],
) -> tuple[Character, Character] | None:
    """The next pair for `seat` to vote on: the fewest votes between both
    first, then the pair of portrayed players that met the least, then the
    closest ratings; random among the rest, the same until something
    changes. Shown in random order."""
    voted = {(v.first_id, v.second_id) for v in _mine(votes, seat)}
    left = [p for p in _pairs(entries, seat) if _pair(p[0].id, p[1].id) not in voted]
    if not left:
        return None
    counts: Counter[uuid.UUID] = Counter()
    for v in votes:
        counts[v.first_id] += 1
        counts[v.second_id] += 1
    subjects = {c.id: c.subject_seat_id for c in entries}
    met: Counter[tuple[str, str]] = Counter()
    for v in votes:
        if v.first_id in subjects and v.second_id in subjects:
            met[
                tuple(sorted(map(str, (subjects[v.first_id], subjects[v.second_id]))))
            ] += 1
    ratings = {s.challenger.id: s.rating for s in standings(entries, votes)}
    rng = random.Random(f"{server.id}:{seat.id}:{day}:{len(voted)}:{len(votes)}")
    rng.shuffle(left)

    def key(pair: tuple[Character, Character]) -> tuple:
        a, b = pair
        return (
            counts[a.id] + counts[b.id],
            met[tuple(sorted((str(a.subject_seat_id), str(b.subject_seat_id))))],
            abs(ratings[a.id] - ratings[b.id]),
        )

    a, b = min(left, key=key)
    return (a, b) if rng.random() < 0.5 else (b, a)


def _pack_reason(day: int) -> str:
    return f"arena-pack:{day}"


def state(
    session: Session,
    server: Server,
    seat: ServerSeat,
    day: int,
    *,
    with_matchup: bool = True,
) -> ArenaState:
    """`seat`'s Arena on `day`, with its next matchup unless not
    `with_matchup` (cheaper). The finales must be decided (`finale.settle`)."""
    week = open_week(server, day)
    if week is None:
        return ArenaState()
    entries = challengers(session, server, week, ranked=with_matchup)
    votes = _votes(session, server, week)
    mine = _mine(votes, seat)
    pairs = len(_pairs(entries, seat))
    cap = rules.arena_daily_cap(
        pairs - sum(v.day < day for v in mine), ends_on(week) - day + 1
    )
    today = sum(v.day == day for v in mine)
    return ArenaState(
        week=week,
        challengers=len(entries),
        votes_today=today,
        cap=cap,
        rewarded=bool(stars.granted(session, seat.id, [_pack_reason(day)])),
        matchup=_matchup(server, seat, day, entries, votes)
        if with_matchup and today < cap
        else None,
    )


class VoteRejected(Exception):
    pass


def vote(
    session: Session,
    server: Server,
    seat: ServerSeat,
    day: int,
    pair: tuple[uuid.UUID, uuid.UUID],
    winner: uuid.UUID | None,
) -> None:
    """Votes for `winner`, one of `pair`, or a draw without one; earns the
    day's pack stars with its last vote. Commits. Raises `VoteRejected`."""
    week = open_week(server, day)
    if week is None:
        raise VoteRejected("The Arena isn't open")
    a, b = pair
    if a == b:
        raise VoteRejected("A matchup takes two challengers")
    if winner is not None and winner not in pair:
        raise VoteRejected("The winner must be one of the matchup")
    current = state(session, server, seat, day, with_matchup=False)
    if current.votes_today >= current.cap:
        raise VoteRejected("That's all for today")
    entries = {c.id: c for c in challengers(session, server, week, ranked=False)}
    if a not in entries or b not in entries:
        raise VoteRejected("Both challengers must be in the Arena")
    if seat.id in (entries[a].artist_seat_id, entries[b].artist_seat_id):
        raise VoteRejected("You can't vote on your own drawings")
    first, second = _pair(a, b)
    session.add(
        ArenaVote(
            server_id=server.id,
            voter_seat_id=seat.id,
            week=week,
            day=day,
            first_id=first,
            second_id=second,
            winner_id=winner,
        )
    )
    try:
        session.flush()
    except IntegrityError as error:
        session.rollback()
        raise VoteRejected("You voted on this matchup already") from error
    if current.votes_today + 1 >= current.pack and not current.rewarded:
        session.add(stars.grant(seat.id, _pack_reason(day), rules.ARENA_PACK_STARS))
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        raise VoteRejected("You voted on this matchup already") from error


def _decide(session: Session, server: Server, week: int) -> list[ArenaHero]:
    """The Arena's result: the top of its ranking crowned, each character
    taking the rarity of its place; one row without a character if it had
    no challengers."""
    ranked = standings(
        challengers(session, server, week), _votes(session, server, week)
    )
    if not ranked:
        return [ArenaHero(server_id=server.id, week=week)]
    heroes = []
    for place, (s, rarity) in enumerate(zip(ranked, rules.ARENA_RARITIES), 1):
        s.challenger.rarity = rarity.value
        heroes.append(
            ArenaHero(
                server_id=server.id,
                week=week,
                character_id=s.challenger.id,
                place=place,
                rarity=rarity.value,
                rating=s.rating,
                score=s.score,
                matchups=s.matchups,
            )
        )
    return heroes


def settle(session: Session, server: Server) -> None:
    """Decides every Arena whose week of votes is over and isn't yet, once
    its finale is. Commits."""
    if speed.is_speed(server):
        return
    today = days.current_day(server)
    decided = set(
        session.scalars(select(ArenaHero.week).where(ArenaHero.server_id == server.id))
    )
    finales = set(
        session.scalars(select(WeeklyHero.day).where(WeeklyHero.server_id == server.id))
    )
    heroes = []
    week = finale.finale_day(server, 1)
    while ends_on(week) < today:
        if week not in decided and week in finales:
            heroes.extend(_decide(session, server, week))
        week += 7
    if not heroes:
        return
    session.add_all(heroes)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()  # Someone else decided it at the same time.


def latest_week(session: Session, server: Server) -> int | None:
    """The latest decided Arena, with or without winners."""
    return session.scalar(
        select(func.max(ArenaHero.week)).where(ArenaHero.server_id == server.id)
    )


def winners_of(session: Session, server: Server, week: int) -> list[ArenaHero]:
    """The winners the Arena of `week` crowned, by place."""
    return list(
        session.scalars(
            select(ArenaHero)
            .where(
                ArenaHero.server_id == server.id,
                ArenaHero.week == week,
                ArenaHero.character_id.is_not(None),
            )
            .order_by(ArenaHero.place)
            .options(selectinload(ArenaHero.character))
        )
    )


def latest_winners(session: Session, server: Server) -> list[ArenaHero]:
    """The winners of the latest decided Arena, by place; none if it had
    none, or before the first one."""
    week = latest_week(session, server)
    return [] if week is None else winners_of(session, server, week)


def ranking(session: Session, server: Server, week: int) -> list[Standing]:
    """The decided Arena of `week`, best first: its winners first, by place,
    then the others by their standing."""
    ranked = standings(
        challengers(session, server, week), _votes(session, server, week)
    )
    places = {h.character_id: h.place for h in winners_of(session, server, week)}
    return sorted(
        ranked,
        key=lambda s: places.get(s.challenger.id, len(places) + 1 + ranked.index(s)),
    )
