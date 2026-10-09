from datetime import UTC, datetime

from app import days
from app.models import Server
from app.premade_prompts import PREMADE_PROMPTS
from app.rules import Theme
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_launch import LaunchTestCase
from tests.test_setup import ADMIN, FRIEND_SUBJECTS

SAM = FRIEND_SUBJECTS[0]


class TodayTests(LaunchTestCase):
    def setUp(self) -> None:
        super().setUp()
        # A test session with Alex (seat 0) and Sam (seat 1).
        self.code = self.create(is_test=True).json()["code"]
        self.sign_up(SAM, "Sam")
        self.claim(self.code, 1, SAM)
        self.start(self.code)
        for subject in (ADMIN, SAM):
            self.draw_all(self.code, subject)
            self.finish(self.code, subject)

    def today(self, subject: str = ADMIN):
        return self.get(f"/servers/{self.code}/today", subject).json()

    def post(self, path: str, subject: str = ADMIN, json=None):
        return self.client.post(
            f"/servers/{self.code}/{path}",
            json=json,
            headers=bearer(make_token(subject)),
        )

    def draw(self, subject: str = ADMIN):
        return self.client.put(
            f"/servers/{self.code}/today/challenger",
            json={"sketch": SKETCH},
            headers=bearer(make_token(subject)),
        )

    def test_day_one_starts_with_a_prompt_to_write(self) -> None:
        today = self.today()
        self.assertEqual((today["day"], today["theme"]), (1, "forest"))
        self.assertIsNone(today["to_draw"])
        self.assertIsNone(today["prompt"]["title"])
        # Not yourself, and not Sam, who draws it tomorrow.
        self.assertNotIn(today["prompt"]["subject_position"], {0, 1})
        self.assertEqual(self.today(), today, "the subject stays the same")
        self.assertEqual(
            self.draw().json()["detail"], "There's no prompt to draw today"
        )

    def test_a_prompt_is_written_once(self) -> None:
        response = self.post("today/prompt", json={"title": " The Owl King "})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["prompt"]["title"], "The Owl King")
        again = self.post("today/prompt", json={"title": "Another"})
        self.assertEqual(again.status_code, 409)
        self.assertEqual(again.json()["detail"], "You wrote today's prompt already")

    def test_the_next_player_draws_the_prompt_or_a_premade_one(self) -> None:
        written = self.post("today/prompt", json={"title": "The Owl King"}).json()
        self.post("today/end")
        self.assertEqual(self.today()["day_ended"], [0])
        self.assertEqual(self.today()["day"], 1, "Sam isn't done yet")
        self.post("today/end", SAM)

        sam = self.today(SAM)
        self.assertEqual(sam["day"], 2)
        self.assertEqual(sam["theme"], "beach")
        self.assertEqual(sam["day_ended"], [])
        self.assertEqual(
            (sam["to_draw"]["author_position"], sam["to_draw"]["title"]),
            (0, "The Owl King"),
        )
        self.assertEqual(
            sam["to_draw"]["subject_position"], written["prompt"]["subject_position"]
        )
        self.assertFalse(sam["to_draw"]["premade"])

        # Sam wrote nothing, so Alex draws a premade forest prompt.
        alex = self.today()["to_draw"]
        self.assertTrue(alex["premade"])
        self.assertEqual(alex["author_position"], 1)
        self.assertIn(alex["title"], PREMADE_PROMPTS[Theme.FOREST])
        self.assertEqual(alex["theme"], "forest")

    def test_a_challenger_joins_the_pool_and_earns_a_pull(self) -> None:
        self.post("days/next")
        response = self.draw(SAM)
        self.assertEqual(response.status_code, 200, response.text)
        challenger = response.json()["to_draw"]["challenger"]
        self.assertEqual(
            (challenger["rarity"], challenger["prompt"], challenger["day"]),
            ("hero", "challenger", 2),
        )
        self.assertEqual(challenger["theme"], "forest")
        pool = [c["id"] for c in self.get(f"/servers/{self.code}/pool").json()]
        self.assertIn(challenger["id"], pool)
        self.assertEqual(
            self.get(f"/servers/{self.code}/gacha", SAM).json()["tickets"], 11
        )
        self.assertEqual(self.files.files[challenger["id"]][2]["kind"], "challenger")

        again = self.draw(SAM)
        self.assertEqual(again.status_code, 409)
        self.assertEqual(again.json()["detail"], "You drew today's challenger already")
        self.assertEqual(
            self.get(f"/servers/{self.code}/gacha", SAM).json()["tickets"], 11
        )

    def test_only_the_admin_starts_the_next_day(self) -> None:
        response = self.post("days/next", SAM)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.post("days/next").json()["day"], 2)
        self.assertEqual(self.today(SAM)["day"], 2)

    def test_the_day_needs_a_launched_game(self) -> None:
        code = self.create(is_test=True).json()["code"]
        response = self.get(f"/servers/{code}/today")
        self.assertEqual(response.status_code, 409)


class RegularDayTests(LaunchTestCase):
    def test_days_change_at_midnight_utc(self) -> None:
        server = Server(
            is_test=False, launched_at=datetime(2026, 10, 9, 23, 30, tzinfo=UTC)
        )
        self.assertEqual(
            days.current_day(server, datetime(2026, 10, 9, 23, 59, tzinfo=UTC)), 1
        )
        self.assertEqual(
            days.current_day(server, datetime(2026, 10, 10, 0, 1, tzinfo=UTC)), 2
        )
        self.assertEqual(
            days.current_day(server, datetime(2026, 10, 16, 12, tzinfo=UTC)), 8
        )

    def test_regular_servers_cannot_end_the_day_early(self) -> None:
        code = self.started_server()
        for subject in [ADMIN, *FRIEND_SUBJECTS]:
            self.draw_all(code, subject)
            self.finish(code, subject)
        for path in ("today/end", "days/next"):
            response = self.client.post(
                f"/servers/{code}/{path}", headers=bearer(make_token(ADMIN))
            )
            self.assertEqual(response.status_code, 409, path)
        today = self.get(f"/servers/{code}/today").json()
        self.assertEqual(today["day"], 1)
