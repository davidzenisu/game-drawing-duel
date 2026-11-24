import uuid

from sqlalchemy import select

from app import arena, rules
from app.models import (
    ArenaHero,
    ArenaVote,
    Character,
    Server,
    ServerSeat,
    StarGrant,
)
from tests.helpers import bearer, make_token
from tests.test_fights import ADMIN, PLAYERS, ROBIN, SAM
from tests.test_finale import FinaleTestCase


class ArenaTestCase(FinaleTestCase):
    """A test session launched on a Monday: everyone draws a challenger on
    days 2 to 5, so week 1 has 12 challengers, all fought that week."""

    def setUp(self) -> None:
        super().setUp()
        # Day 4, from `FinaleTestCase`: days 2 and 3 are drawn.
        self.draw_challengers()
        self.next_day()
        self.draw_challengers()

    def arena(self, subject: str = ADMIN):
        response = self.get(f"/servers/{self.code}/arena", subject)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def vote(self, matchup, winner: int | None = 0, subject: str = ADMIN):
        return self.client.post(
            f"/servers/{self.code}/arena/votes",
            json={
                "challenger_ids": [c["id"] for c in matchup],
                "winner_id": None if winner is None else matchup[winner]["id"],
            },
            headers=bearer(make_token(subject)),
        )

    def stars(self, subject: str = ADMIN) -> int:
        return self.get(f"/servers/{self.code}/gacha", subject).json()["stars"]

    def position(self, subject: str) -> int:
        return PLAYERS.index(subject)

    def vote_all_week(self, prefer: str | None = None) -> None:
        """Everyone votes every day until the Arena's last day, for the
        challenger `prefer` if it's in the matchup, else the first one."""
        while True:
            for subject in PLAYERS:
                while (state := self.arena(subject))["matchup"]:
                    matchup = state["matchup"]
                    ids = [c["id"] for c in matchup]
                    winner = ids.index(prefer) if prefer in ids else 0
                    self.assertEqual(
                        self.vote(matchup, winner, subject).status_code, 200
                    )
            if self.today()["day"] >= 14:
                return
            self.next_day()


class ArenaTests(ArenaTestCase):
    """The Arena, see `app/arena.py`."""

    def test_the_arena_opens_in_the_second_week_with_last_weeks_challengers(
        self,
    ) -> None:
        self.go_to_day(7)
        self.assertIsNone(self.today()["arena"], "not in the first week")
        closed = self.arena()
        self.assertEqual((closed["status"], closed["matchup"]), (None, None))

        self.next_day()
        heroes = {h["character"]["id"] for h in self.today()["weekly_heroes"]}
        self.assertEqual(len(heroes), 3)
        status = self.today()["arena"]
        self.assertEqual((status["week"], status["ends_on"]), (7, 14))
        self.assertEqual(status["challengers"], 12 - 3, "all but the weekly heroes")
        self.assertEqual((status["votes_today"], status["pack"]), (0, rules.ARENA_PACK))
        state = self.arena()
        matchup = state["matchup"]
        self.assertEqual(len(matchup), 2)
        self.assertFalse({c["id"] for c in matchup} & heroes)
        self.assertNotIn(
            self.position(ADMIN),
            [c["artist_position"] for c in matchup],
            "never your own drawings",
        )
        self.assertEqual(self.arena(), state, "the same matchup until you vote")

    def test_votes_earn_the_pack_stars_once_and_stop_at_the_cap(self) -> None:
        self.go_to_day(8)
        before = self.stars()
        # 9 challengers, 3 of them Alex's: 15 pairs to vote on in 7 days,
        # so today's cap is the pack.
        self.assertEqual(self.arena()["status"]["cap"], 10)
        seen = set()
        for n in range(1, 11):
            matchup = self.arena()["matchup"]
            pair = frozenset(c["id"] for c in matchup)
            self.assertNotIn(pair, seen, "each pair once")
            seen.add(pair)
            response = self.vote(matchup, None if n == 1 else 0)
            self.assertEqual(response.status_code, 200, response.text)
            status = response.json()["status"]
            self.assertEqual(status["votes_today"], n)
            self.assertEqual(status["rewarded"], n == 10)
            self.assertEqual(
                self.stars(), before + (rules.ARENA_PACK_STARS if n == 10 else 0)
            )
        state = self.arena()
        self.assertIsNone(state["matchup"], "that's all for today")
        self.assertEqual(state["stars"], before + rules.ARENA_PACK_STARS)
        [a, b] = next(iter(seen))
        response = self.client.post(
            f"/servers/{self.code}/arena/votes",
            json={"challenger_ids": [a, b], "winner_id": a},
            headers=bearer(make_token(ADMIN)),
        )
        self.assertEqual(response.status_code, 409)

        # Tomorrow: the 5 pairs left over 6 days, all of them today.
        self.next_day()
        status = self.arena()["status"]
        self.assertEqual(
            (status["cap"], status["pack"], status["votes_today"]), (5, 5, 0)
        )

    def test_the_next_matchup_comes_along_to_show_below(self) -> None:
        self.go_to_day(8)
        state = self.arena()
        current = {c["id"] for c in state["matchup"]}
        upcoming = state["next_matchup"]
        self.assertEqual(len(upcoming), 2)
        self.assertNotEqual({c["id"] for c in upcoming}, current, "another pair")
        self.assertNotIn(self.position(ADMIN), [c["artist_position"] for c in upcoming])
        self.assertEqual(self.vote(state["matchup"]).status_code, 200)
        # The app shows the one it had below next, and votes on it.
        response = self.vote(upcoming, None)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["status"]["votes_today"], 2)

    def test_no_next_matchup_below_the_days_last(self) -> None:
        self.go_to_day(8)
        for _ in range(9):
            self.vote(self.arena()["matchup"])
        state = self.arena()
        self.assertEqual(state["status"]["cap"] - state["status"]["votes_today"], 1)
        self.assertIsNotNone(state["matchup"])
        self.assertIsNone(state["next_matchup"])

    def test_votes_must_be_on_the_arena_and_not_your_own(self) -> None:
        self.go_to_day(8)
        matchup = self.arena()["matchup"]
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            entries = arena.challengers(session, server, 7)
            own = next(
                str(c.id) for c in entries if c.artist.position == self.position(ADMIN)
            )
            other = next(
                str(c.id) for c in entries if c.artist.position != self.position(ADMIN)
            )
        hero = self.today()["weekly_heroes"][0]["character"]["id"]
        for ids, winner in (
            ([own, other], other),
            ([hero, other], other),
            ([other, other], other),
            ([c["id"] for c in matchup], str(uuid.uuid4())),
        ):
            response = self.client.post(
                f"/servers/{self.code}/arena/votes",
                json={"challenger_ids": ids, "winner_id": winner},
                headers=bearer(make_token(ADMIN)),
            )
            self.assertEqual(response.status_code, 409, (ids, response.text))
        self.assertEqual(self.vote(matchup).status_code, 200)
        self.assertEqual(self.vote(matchup).status_code, 409, "once per pair")

    def test_matchups_spread_the_votes(self) -> None:
        self.go_to_day(8)
        # Sam and Robin each vote 4 times: every challenger they can vote on
        # gets votes before any gets many.
        for subject in (SAM, ROBIN):
            for _ in range(4):
                self.assertEqual(
                    self.vote(self.arena(subject)["matchup"], 0, subject).status_code,
                    200,
                )
        with self.session_factory() as session:
            votes = session.scalars(select(ArenaVote)).all()
        counts = {}
        for v in votes:
            for c in (v.first_id, v.second_id):
                counts[c] = counts.get(c, 0) + 1
        self.assertEqual(len(counts), 9, "every challenger met one already")
        # Nobody votes on their own drawings, so it can't always be even.
        self.assertLessEqual(max(counts.values()) - min(counts.values()), 2)

    def test_the_top_three_become_arena_winners_for_the_arena_banner(self) -> None:
        self.go_to_day(8)
        heroes = {h["character"]["id"] for h in self.today()["weekly_heroes"]}
        favourite = next(
            c["id"] for c in (self.arena(s)["matchup"] for s in PLAYERS) for c in c
        )
        self.assertEqual(self.today()["arena_heroes"], [])
        closed = self.client.post(
            f"/servers/{self.code}/pulls",
            json={"count": 1, "banner": "arena"},
            headers=bearer(make_token(ADMIN)),
        )
        self.assertEqual(closed.status_code, 409)
        self.assertIn("Arena", closed.json()["detail"])

        self.vote_all_week(prefer=favourite)
        self.assertEqual(self.today()["day"], 14)
        self.assertEqual(self.today()["arena_heroes"], [], "voting ends on Sunday")

        self.next_day()
        winners = self.today()["arena_heroes"]
        self.assertEqual(
            [(w["place"], w["character"]["rarity"], w["week"]) for w in winners],
            [(1, "legend", 7), (2, "hero", 7), (3, "adventurer", 7)],
        )
        self.assertEqual(winners[0]["character"]["id"], favourite)
        self.assertFalse({w["character"]["id"] for w in winners} & heroes)
        pool = {
            c["id"]: c["rarity"] for c in self.get(f"/servers/{self.code}/pool").json()
        }
        self.assertEqual(
            [pool.get(w["character"]["id"]) for w in winners],
            ["legend", "hero", "adventurer"],
        )
        gacha = self.get(f"/servers/{self.code}/gacha").json()
        self.assertEqual(
            set(gacha["arena_rate_up"]), {w["character"]["id"] for w in winners}
        )
        with self.session_factory() as session:
            top = session.scalar(
                select(ArenaHero).where(ArenaHero.place == 1, ArenaHero.week == 7)
            )
            self.assertEqual(top.score, top.matchups, "won every matchup")
        # The Arena of week 2's challengers is open now.
        self.assertEqual(self.today()["arena"]["week"], 14)

        self.pull_launch_bonus_on_arena()

    def pull_launch_bonus_on_arena(self) -> None:
        response = self.client.post(
            f"/servers/{self.code}/pulls",
            json={"count": 10, "banner": "arena"},
            headers=bearer(make_token(ADMIN)),
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(len(response.json()["outcomes"]), 10)

    def test_an_arena_without_challengers_crowns_nobody(self) -> None:
        # Nobody draws in week 2, so week 2's Arena is empty.
        self.go_to_day(22)
        self.assertEqual(self.today()["arena_heroes"], [])
        with self.session_factory() as session:
            decided = session.scalars(
                select(ArenaHero).where(ArenaHero.week == 14)
            ).all()
        self.assertEqual([h.character_id for h in decided], [None])


class ArenaUnitTests(ArenaTestCase):
    def test_the_pack_reward_is_granted_once(self) -> None:
        self.go_to_day(8)
        for _ in range(10):
            self.vote(self.arena()["matchup"])
        with self.session_factory() as session:
            grants = session.scalars(
                select(StarGrant)
                .join(ServerSeat, ServerSeat.id == StarGrant.seat_id)
                .where(StarGrant.reason == "arena-pack:8")
            ).all()
        self.assertEqual([g.stars for g in grants], [rules.ARENA_PACK_STARS])

    def test_challengers_come_in_the_order_of_their_weeks_ranking(self) -> None:
        self.go_to_day(8)
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            ranked = [r.challenger.id for r in arena.finale.ranking(session, server, 7)]
            entries = [c.id for c in arena.challengers(session, server, 7)]
            self.assertEqual(entries, ranked[3:])
            self.assertTrue(
                all(session.get(Character, c).rarity == "hero" for c in entries),
                "not crowned (yet)",
            )
