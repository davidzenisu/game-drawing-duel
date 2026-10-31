import uuid
from datetime import UTC, datetime

from sqlalchemy import delete, select

from app.models import Boost, Character, Server, ServerSeat, WeeklyHero
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_fights import ADMIN, PLAYERS, FightTestCase


class FinaleTests(FightTestCase):
    """The weekly finale, see `app/finale.py`."""

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

    def test_the_most_stars_join_the_pool_as_a_hero(self) -> None:
        # Day 4: one of day 3's challengers gets more boost stars than any.
        favourite = self.challengers(3)[1]
        self.boost(favourite, 3)
        self.go_to_day(7)
        self.assertIsNone(self.ranking(), "not before the week is over")
        self.assertIsNone(self.today()["weekly_hero"])
        pool = {c["id"] for c in self.get(f"/servers/{self.code}/pool").json()}
        self.assertNotIn(favourite, pool)

        self.next_day()
        hero = self.today()["weekly_hero"]
        self.assertEqual(hero["character"]["id"], favourite)
        self.assertEqual(hero["character"]["rarity"], "hero")
        self.assertEqual((hero["day"], hero["stars"]), (7, 3 + 3 + 3))
        pool = {c["id"] for c in self.get(f"/servers/{self.code}/pool").json()}
        self.assertIn(favourite, pool)
        # The other challengers stay out of the pool.
        week = set(self.challengers(2)) | set(self.challengers(3))
        self.assertFalse(pool & (week - {favourite}))

    def test_everyone_sees_the_ranking_of_every_challenger(self) -> None:
        favourite = self.challengers(2)[0]
        self.boost(favourite, 2)
        # Day 7, a Sunday: challengers drawn today are boosted next week.
        self.go_to_day(7)
        self.draw_challengers()
        self.next_day()
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

    def test_a_week_without_challengers_has_no_hero(self) -> None:
        self.go_to_day(15)
        self.assertIsNone(self.today()["weekly_hero"])
        self.assertEqual(self.ranking(), {"day": 14, "challengers": []})
