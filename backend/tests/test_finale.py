import random
import uuid
from datetime import UTC, datetime

from sqlalchemy import delete, select

from app import pulls, rules
from app.gacha import Banner
from app.models import (
    Boost,
    Character,
    PullGrant,
    Server,
    ServerSeat,
    WeeklyHero,
)
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_fights import ADMIN, PLAYERS, FightTestCase


class FinaleTestCase(FightTestCase):
    """A test session launched on a Monday, on day 3."""

    def setUp(self) -> None:
        super().setUp()
        # Day 1 is a Monday: day 7 ends the week, day 8 starts the next.
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            server.launched_at = datetime(2026, 10, 5, 9, tzinfo=UTC)
            # Finales decided while the launch date was a different weekday.
            session.execute(delete(WeeklyHero).where(WeeklyHero.server_id == server.id))
            session.commit()
        # Day 3: everyone draws another challenger. Everyone has one of
        # day 2's to boost, so chance gives each 3 stars.
        self.draw_challengers()
        self.next_day()

    def draw_challengers(self) -> None:
        for subject in PLAYERS:
            self.client.put(
                f"/servers/{self.code}/today/challenger",
                json={"sketch": SKETCH},
                headers=bearer(make_token(subject)),
            )

    def go_to_day(self, day: int) -> None:
        while self.today()["day"] < day:
            self.next_day()

    def challengers(self, day: int) -> list[str]:
        """The challengers drawn on `day`."""
        with self.session_factory() as session:
            return [
                str(c.id)
                for c in session.scalars(
                    select(Character)
                    .join(Server, Server.id == Character.server_id)
                    .where(
                        Server.code == self.code,
                        Character.day == day,
                        Character.assignment_id.is_(None),
                    )
                )
            ]

    def boost(self, challenger: str, stars: int) -> None:
        """Extra boost stars, as if more players gave them. Stored on day 1,
        before any boosting, so chance still spreads everyone's own."""
        with self.session_factory() as session:
            seat = session.scalar(
                select(ServerSeat.id)
                .join(Server, Server.id == ServerSeat.server_id)
                .where(Server.code == self.code, ServerSeat.position == 0)
            )
            session.add(
                Boost(
                    booster_seat_id=seat,
                    challenger_id=uuid.UUID(challenger),
                    day=1,
                    stars=stars,
                )
            )
            session.commit()

    def ranking(self, subject: str = ADMIN):
        response = self.get(f"/servers/{self.code}/ranking", subject)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()


class FinaleTests(FinaleTestCase):
    """The weekly finale, see `app/finale.py`."""

    def pool(self) -> set[str]:
        return {c["id"] for c in self.get(f"/servers/{self.code}/pool").json()}

    def test_the_top_three_join_the_pool_as_a_legend_a_hero_and_an_adventurer(
        self,
    ) -> None:
        # 3 + 3 from chance each, and more for three of them.
        first, second = self.challengers(3)[:2]
        third = self.challengers(2)[0]
        self.boost(first, 5)
        self.boost(second, 3)
        self.boost(third, 1)
        self.go_to_day(7)
        self.assertIsNone(self.ranking(), "not before the week is over")
        self.assertEqual(self.today()["weekly_heroes"], [])
        self.assertFalse(self.pool() & {first, second, third})

        self.next_day()
        heroes = self.today()["weekly_heroes"]
        self.assertEqual(
            [
                (h["character"]["id"], h["place"], h["stars"], h["character"]["rarity"])
                for h in heroes
            ],
            [
                (first, 1, 11, "legend"),
                (second, 2, 9, "hero"),
                (third, 3, 7, "adventurer"),
            ],
        )
        self.assertEqual({h["day"] for h in heroes}, {7})
        pool = {
            c["id"]: c["rarity"] for c in self.get(f"/servers/{self.code}/pool").json()
        }
        self.assertEqual(
            [pool.get(c) for c in (first, second, third)],
            ["legend", "hero", "adventurer"],
            "pulled with their new rarities",
        )
        # The other challengers stay out of the pool.
        week = set(self.challengers(2)) | set(self.challengers(3))
        self.assertFalse(pool.keys() & (week - {first, second, third}))

        ranking = self.ranking()
        self.assertEqual(
            [(r["place"], r["hero_rarity"]) for r in ranking["challengers"]],
            [(1, "legend"), (2, "hero"), (3, "adventurer")]
            + [(place, None) for place in range(4, 7)],
        )
        # Only the heroes are rate-up: no starter legend joins them.
        rate_up = self.get(f"/servers/{self.code}/gacha").json()["rate_up"]
        self.assertEqual(set(rate_up), {first, second, third})
        for subject in PLAYERS:
            gacha = self.get(f"/servers/{self.code}/gacha", subject).json()
            self.assertEqual(set(gacha["rate_up"]), set(rate_up))

    def test_every_week_crowns_three_whatever_their_stars(self) -> None:
        # 6 stars each: the tiebreaks decide.
        self.go_to_day(8)
        heroes = self.today()["weekly_heroes"]
        ranked = self.ranking()["challengers"]
        self.assertEqual(
            [
                (h["character"]["id"], h["place"], h["character"]["rarity"])
                for h in heroes
            ],
            [
                (r["character"]["id"], place, rarity)
                for r, place, rarity in zip(
                    ranked, (1, 2, 3), ("legend", "hero", "adventurer")
                )
            ],
        )
        self.assertEqual({h["stars"] for h in heroes}, {6})

    def test_ties_go_to_artists_not_ranked_yet_then_the_most_boosted(
        self,
    ) -> None:
        # One more star for a day 2 challenger: its artist's day 3 one ties
        # with the others on its own stars, but not on its artist's. Its
        # artist is ranked already, though: the other artists come first.
        boosted = self.challengers(2)[0]
        self.boost(boosted, 1)
        self.go_to_day(8)
        ranked = self.ranking()["challengers"]
        self.assertEqual(ranked[0]["character"]["id"], boosted)
        by_artist: dict[int, int] = {}
        for r in ranked:
            artist = r["character"]["artist_position"]
            by_artist[artist] = by_artist.get(artist, 0) + r["stars"] - 3
        for r in ranked:
            self.assertEqual(
                r["artist_boost_stars"], by_artist[r["character"]["artist_position"]]
            )
        sibling = next(
            r
            for r in ranked
            if r["character"]["artist_position"]
            == ranked[0]["character"]["artist_position"]
            and r["character"]["id"] != boosted
        )
        artists = [r["character"]["artist_position"] for r in ranked]
        self.assertEqual(len(set(artists[:3])), 3, "the top 3 by three artists")
        self.assertEqual(
            ranked[3], sibling, "then its artist's 7 boost stars come first"
        )
        self.assertEqual(
            rules.finale_order(
                [
                    rules.FinaleEntry(
                        r["character"]["artist_position"],
                        r["stars"] - 3,
                        r["artist_boost_stars"],
                        r["wins"],
                        r["fights"],
                        r["character"]["day"],
                    )
                    for r in ranked
                ]
            ),
            list(range(len(ranked))),
        )
        self.assertEqual([r["place"] for r in ranked], list(range(1, 7)))

    def test_everyone_sees_the_ranking_of_every_challenger(self) -> None:
        favourite = self.challengers(2)[0]
        self.boost(favourite, 2)
        # Day 7, a Sunday: challengers drawn today are boosted next week.
        with self.without_rest():
            self.go_to_day(7)
            self.draw_challengers()
            self.next_day()
            self.today()
        ranking = self.ranking()
        self.assertEqual(ranking["day"], 7)
        ranked = [r["character"]["id"] for r in ranking["challengers"]]
        self.assertCountEqual(ranked, self.challengers(2) + self.challengers(3))
        self.assertEqual(ranked[0], favourite)
        stars = [r["stars"] for r in ranking["challengers"]]
        self.assertEqual(stars, sorted(stars, reverse=True))
        self.assertEqual(stars, [8, 6, 6, 6, 6, 6], "3 + 3 from chance each")
        # Every one of them was fought once that week.
        self.assertEqual([r["fights"] for r in ranking["challengers"]], [1] * 6)
        for subject in PLAYERS:
            self.assertEqual(self.ranking(subject), ranking)

    def test_a_challenger_ranks_in_the_week_of_its_fight(self) -> None:
        # Drawn on Friday (day 5), fought on Sunday: this week. Drawn on
        # Saturday (day 6), boosted on Sunday and fought on Monday: next week.
        with self.without_rest():
            self.go_to_day(5)
            self.draw_challengers()
            self.next_day()
            self.draw_challengers()
            self.go_to_day(8)
            self.today()
        ranked = {r["character"]["id"] for r in self.ranking()["challengers"]}
        self.assertTrue(set(self.challengers(5)) <= ranked)
        self.assertFalse(set(self.challengers(6)) & ranked, "not fought yet")
        self.assertTrue(set(self.challengers(2)) <= ranked)
        entries = self.ranking()["challengers"]
        self.assertEqual(
            [e["fights"] for e in entries], [1] * len(entries), "all fought"
        )

        with self.without_rest():
            self.go_to_day(15)
            self.today()
        next_week = self.ranking()
        self.assertEqual(next_week["day"], 14)
        ranked = {r["character"]["id"] for r in next_week["challengers"]}
        self.assertTrue(set(self.challengers(6)) <= ranked, "fought on Monday")
        self.assertFalse(set(self.challengers(5)) & ranked)

    def test_the_ranking_tells_who_wrote_boosted_and_fought_each(self) -> None:
        # Day 4: Alex writes a prompt of Robin; someone else draws it the
        # next day, handed it at random.
        written = self.post(
            "today/prompt", ADMIN, {"subject_position": 2, "title": "Sauna Lord"}
        )
        self.assertEqual(written.status_code, 200, written.text)
        favourite = self.challengers(3)[0]
        self.boost(favourite, 2)
        self.next_day()
        self.draw_challengers()
        with self.without_rest():
            self.go_to_day(8)
            self.today()
        entries = {r["character"]["id"]: r for r in self.ranking()["challengers"]}

        written_ = [
            e
            for e in (entries[c] for c in self.challengers(5))
            if not e["default_prompt"]
        ]
        self.assertEqual(len(written_), 1, "only Alex wrote one")
        self.assertEqual(written_[0]["prompt_author_position"], 0)
        self.assertNotEqual(
            written_[0]["character"]["artist_position"], 0, "not drawn by Alex"
        )
        others = [entries[c] for c in self.challengers(3)]
        self.assertTrue(all(e["default_prompt"] for e in others), "nobody wrote one")
        authors = [e["prompt_author_position"] for e in others]
        self.assertEqual(sorted(authors), [0, 1, 2], "everyone's prompt drawn once")
        for entry in others:
            self.assertNotEqual(
                entry["prompt_author_position"],
                entry["character"]["artist_position"],
                "nobody draws their own prompt",
            )
        for entry in entries.values():
            self.assertEqual(
                sum(b["stars"] for b in entry["boosts"]), entry["stars"] - 3
            )
            self.assertEqual(len(entry["fought_by"]), entry["fights"])
            self.assertEqual(
                sum(f["challenger_won"] for f in entry["fought_by"]), entry["wins"]
            )
        # Alex's own 2 stars, and the ones chance spread for players.
        self.assertIn(
            {"booster_position": 0, "stars": 2, "by_chance": False},
            entries[favourite]["boosts"],
        )
        self.assertTrue(
            all(b["by_chance"] for e in others[1:] for b in e["boosts"]),
            "nobody boosted themselves",
        )
        for entry in entries.values():
            for fight in entry["fought_by"]:
                self.assertNotEqual(
                    fight["player_position"],
                    entry["character"]["artist_position"],
                    "never by its artist",
                )

    def test_both_banners_pull_the_weekly_hero(self) -> None:
        self.go_to_day(8)
        hero = self.today()["weekly_heroes"][0]["character"]["id"]
        gacha = self.get(f"/servers/{self.code}/gacha").json()
        weekly = self.post_pulls(min(gacha["tickets"], 10), "weekly")
        self.assertEqual(weekly.status_code, 200, weekly.text)
        pool = {c["id"] for c in self.get(f"/servers/{self.code}/pool").json()}
        self.assertIn(hero, pool)
        for outcome in weekly.json()["outcomes"]:
            self.assertIn(outcome["character"]["id"], pool)
        # The week's new hero is on the standard banner too: with enough
        # pulls, it comes up there as well.
        with self.session_factory() as session:
            seat = session.scalar(
                select(ServerSeat)
                .join(Server, Server.id == ServerSeat.server_id)
                .where(Server.code == self.code, ServerSeat.position == 1)
            )
            session.add_all(
                PullGrant(seat_id=seat.id, reason=f"test:{n}") for n in range(300)
            )
            session.flush()
            outcomes = pulls.pull(session, seat, 300, Banner.STANDARD, random.Random(1))
            pulled = {str(o.character.id) for o in outcomes}
            session.rollback()
        self.assertIn(hero, pulled)
        self.assertLessEqual(pulled, pool)

    def post_pulls(self, count: int, banner: str, subject: str = ADMIN):
        return self.client.post(
            f"/servers/{self.code}/pulls",
            json={"count": count, "banner": banner},
            headers=bearer(make_token(subject)),
        )

    def test_a_week_without_challengers_has_no_heroes(self) -> None:
        self.go_to_day(15)
        self.assertEqual(self.today()["weekly_heroes"], [])
        ranking = self.ranking()
        self.assertEqual((ranking["day"], ranking["challengers"]), (14, []))
        self.assertIsNone(
            ranking["boost_balance"], "launched before the balance's first week"
        )
