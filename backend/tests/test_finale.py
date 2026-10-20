import uuid
from datetime import UTC, datetime

from sqlalchemy import select

from app.models import Character, Fight, Server
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_fights import ADMIN, PLAYERS, FightTestCase


class FinaleTests(FightTestCase):
    """The weekly finale, see `app/finale.py`."""

    def setUp(self) -> None:
        super().setUp()
        # Day 1 is a Monday: day 7 is the week's finale, day 8 starts the next.
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            server.launched_at = datetime(2026, 10, 5, 9, tzinfo=UTC)
            session.commit()
        # Day 3: everyone sends a basic against a challenger of day 2, and
        # draws another for day 4. One basic star never beats a challenger's
        # three, so every challenger fought wins.
        self.fight_with_a_basic()
        for subject in PLAYERS:
            self.client.put(
                f"/servers/{self.code}/today/challenger",
                json={"sketch": SKETCH},
                headers=bearer(make_token(subject)),
            )
        self.next_day()
        # Day 4: the same against day 3's. Nobody draws, so no fights later.
        self.fight_with_a_basic()
        self.next_day()

    def fight_with_a_basic(self) -> None:
        for subject in PLAYERS:
            collection = self.get(f"/servers/{self.code}/collection", subject).json()
            basic = next(
                o["character"]["id"]
                for o in collection
                if o["character"]["rarity"] == "basic"
            )
            response = self.pick([basic], subject)
            self.assertEqual(response.status_code, 200, response.text)

    def go_to_day(self, day: int) -> None:
        while self.today()["day"] < day:
            self.next_day()

    def fought(self) -> dict[str, str]:
        """The challengers fought this week, by id, with their artist's
        subject."""
        with self.session_factory() as session:
            challengers = session.scalars(
                select(Character)
                .join(Fight, Fight.challenger_id == Character.id)
                .join(Server, Server.id == Character.server_id)
                .where(Server.code == self.code)
            ).unique()
            return {str(c.id): PLAYERS[c.artist.position] for c in challengers}

    def vote(self, pair: dict, chosen: str, subject: str = ADMIN):
        other = next(c["id"] for c in pair.values() if c["id"] != chosen)
        return self.post(
            "today/finale", subject, {"chosen_id": chosen, "other_id": other}
        )

    def test_the_finale_is_on_the_last_day_of_the_week(self) -> None:
        self.assertIsNone(self.today()["finale"])
        self.go_to_day(6)
        self.assertIsNone(self.today()["finale"])
        some = next(iter(self.fought()))
        response = self.post("today/finale", json={"chosen_id": some, "other_id": some})
        self.assertEqual(response.status_code, 409)

        self.next_day()
        step = self.today()["finale"]
        self.assertEqual(step["contenders"], len(self.fought()))
        self.next_day()
        self.assertIsNone(self.today()["finale"])

    def test_every_pair_once_but_none_with_your_own_challenger(self) -> None:
        self.go_to_day(7)
        fought = self.fought()
        others = [c for c, artist in fought.items() if artist != ADMIN]
        step = self.today()["finale"]
        self.assertEqual(step["pairs"], len(others) * (len(others) - 1) // 2)
        self.assertGreater(step["pairs"], 0)

        seen = set()
        while step["pair"] is not None:
            pair = step["pair"]
            ids = {pair["left"]["id"], pair["right"]["id"]}
            self.assertLessEqual(ids, set(others))
            self.assertNotIn(frozenset(ids), seen)
            seen.add(frozenset(ids))
            response = self.vote(pair, pair["left"]["id"])
            self.assertEqual(response.status_code, 200, response.text)
            step = response.json()["finale"]
            self.assertEqual(step["votes"], len(seen))
        self.assertEqual(step["votes"], step["pairs"])

        # Voting again on a pair, or on your own challenger, isn't allowed.
        a, b = sorted(next(iter(seen)))
        response = self.post("today/finale", json={"chosen_id": a, "other_id": b})
        self.assertEqual(response.status_code, 409)
        own = next((c for c, artist in fought.items() if artist == ADMIN), None)
        if own is not None:
            response = self.post(
                "today/finale", json={"chosen_id": own, "other_id": others[0]}
            )
            self.assertEqual(response.status_code, 409)

    def test_the_most_stars_join_the_pool_as_a_hero(self) -> None:
        self.go_to_day(7)
        fought = self.fought()
        # A challenger gets every vote it can from the two players who didn't
        # draw it.
        favourite, artist = next(iter(fought.items()))
        votes = 0
        for subject in (p for p in PLAYERS if p != artist):
            step = self.today(subject)["finale"]
            while step["pair"] is not None:
                pair = step["pair"]
                ids = [pair["left"]["id"], pair["right"]["id"]]
                chosen = favourite if favourite in ids else ids[0]
                votes += chosen == favourite
                step = self.vote(pair, chosen, subject).json()["finale"]
        pool = {c["id"] for c in self.get(f"/servers/{self.code}/pool").json()}
        self.assertNotIn(favourite, pool)
        self.assertIsNone(self.today()["weekly_hero"])

        self.next_day()
        hero = self.today()["weekly_hero"]
        self.assertEqual(hero["character"]["id"], favourite)
        self.assertEqual(hero["character"]["rarity"], "hero")
        self.assertEqual(hero["day"], 7)
        self.assertEqual(hero["votes"], votes)
        self.assertEqual(hero["stars"], 3 + votes)
        pool = {c["id"] for c in self.get(f"/servers/{self.code}/pool").json()}
        self.assertIn(favourite, pool)
        # The other challengers stay out of the pool.
        self.assertFalse(pool & (set(fought) - {favourite}))

    def test_the_weekly_hero_and_their_legends_are_rate_up_for_a_week(
        self,
    ) -> None:
        self.go_to_day(7)
        self.assertEqual(self.get(f"/servers/{self.code}/gacha").json()["rate_up"], [])

        self.next_day()
        hero = self.today()["weekly_hero"]["character"]
        # The setup's legends are of random players: make one of the hero's.
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            legend = session.scalar(
                select(Character).where(
                    Character.server_id == server.id,
                    Character.rarity == "legend",
                    Character.assignment_id.is_not(None),
                )
            )
            legend.subject_seat_id = session.get(
                Character, uuid.UUID(hero["id"])
            ).subject_seat_id
            session.commit()
        pool = self.get(f"/servers/{self.code}/pool").json()
        legends = {
            c["id"]
            for c in pool
            if c["rarity"] == "legend"
            and c["subject_position"] == hero["subject_position"]
        }
        self.assertIn(str(legend.id), legends)
        rate_up = self.get(f"/servers/{self.code}/gacha").json()["rate_up"]
        self.assertEqual(set(rate_up), {hero["id"], *legends})
        # Everyone sees the same rate-up.
        for subject in PLAYERS:
            gacha = self.get(f"/servers/{self.code}/gacha", subject).json()
            self.assertEqual(set(gacha["rate_up"]), set(rate_up))

    def test_the_weekly_banner_pulls_the_hero_the_standard_one_never(self) -> None:
        self.go_to_day(8)
        hero = self.today()["weekly_hero"]["character"]["id"]
        gacha = self.get(f"/servers/{self.code}/gacha").json()
        weekly = self.post_pulls(min(gacha["tickets"], 10), "weekly")
        self.assertEqual(weekly.status_code, 200, weekly.text)
        pool = {c["id"] for c in self.get(f"/servers/{self.code}/pool").json()}
        for outcome in weekly.json()["outcomes"]:
            self.assertIn(outcome["character"]["id"], pool)
        # The standard banner is the setup drawings only: no heroes.
        for subject in PLAYERS:
            if subject == ADMIN:
                continue
            tickets = self.get(f"/servers/{self.code}/gacha", subject).json()["tickets"]
            standard = self.post_pulls(min(tickets, 10), "standard", subject).json()
            rarities = {o["character"]["rarity"] for o in standard["outcomes"]}
            self.assertNotIn("hero", rarities)
            self.assertNotIn(hero, {o["character"]["id"] for o in standard["outcomes"]})

    def post_pulls(self, count: int, banner: str, subject: str = ADMIN):
        return self.client.post(
            f"/servers/{self.code}/pulls",
            json={"count": count, "banner": banner},
            headers=bearer(make_token(subject)),
        )

    def test_without_votes_the_fight_stars_decide(self) -> None:
        self.go_to_day(8)
        hero = self.today()["weekly_hero"]
        self.assertIn(hero["character"]["id"], self.fought())
        self.assertEqual((hero["stars"], hero["votes"]), (3, 0))

    def test_a_week_without_winning_challengers_has_no_hero(self) -> None:
        self.go_to_day(15)
        self.assertIsNone(self.today()["weekly_hero"])
