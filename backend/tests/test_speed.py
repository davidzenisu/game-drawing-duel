from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.models import Character, Server
from app.rules import SPEED_DAY_SECONDS
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_launch import LaunchTestCase
from tests.test_setup import ADMIN, FRIEND_SUBJECTS

PLAYERS = (ADMIN, *FRIEND_SUBJECTS)


def _parse(moment: str) -> datetime:
    parsed = datetime.fromisoformat(moment)
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


class SpeedTestCase(LaunchTestCase):
    def setUp(self) -> None:
        super().setUp()
        # A speed mode session of all five players, in its setup.
        self.code = self.create(mode="speed").json()["code"]
        self.join_everyone(self.code)
        self.assertEqual(self.start(self.code).status_code, 200)

    def server(self, subject: str = ADMIN) -> dict:
        return self.get(f"/servers/{self.code}", subject).json()

    def today(self, subject: str = ADMIN) -> dict:
        return self.get(f"/servers/{self.code}/today", subject).json()

    def post(self, path: str, subject: str = ADMIN, json=None):
        return self.client.post(
            f"/servers/{self.code}/{path}",
            json=json,
            headers=bearer(make_token(subject)),
        )

    def rewind(self, seconds: float) -> None:
        """Moves the session `seconds` into the future, as if they passed."""
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            back = timedelta(seconds=seconds)
            for field in ("setup_started_at", "launched_at", "speed_day_started_at"):
                if getattr(server, field) is not None:
                    setattr(server, field, getattr(server, field) - back)
            session.commit()

    def launch(self) -> None:
        for subject in PLAYERS:
            self.draw_all(self.code, subject)
            self.finish(self.code, subject)
        self.assertEqual(self.server()["phase"], "running")

    def write_prompts(self) -> None:
        for i, subject in enumerate(PLAYERS):
            response = self.post(
                "today/prompt",
                subject,
                {"title": "Title", "subject_position": (i + 1) % len(PLAYERS)},
            )
            self.assertEqual(response.status_code, 200, response.text)


class SpeedSetupTests(SpeedTestCase):
    def test_everyone_draws_a_basic_and_a_rarer_character_in_five_minutes(self) -> None:
        server = self.server()
        self.assertEqual((server["mode"], server["phase"]), ("speed", "setup"))
        ends = _parse(server["setup_ends_at"])
        self.assertAlmostEqual((ends - datetime.now(UTC)).total_seconds(), 300, delta=5)
        for position, subject in enumerate(PLAYERS):
            assignments = self.assignments(self.code, subject).json()
            self.assertEqual(assignments[0]["prompt"], "basic")
            self.assertEqual(len(assignments), 2)
            self.assertNotEqual(assignments[1]["prompt"], "basic")
            subjects = [a["subject_position"] for a in assignments]
            self.assertEqual(subjects, [(position + 1) % 5, (position + 2) % 5])

    def test_players_own_only_their_basic_drawing(self) -> None:
        self.launch()
        for subject in PLAYERS:
            collection = self.get(f"/servers/{self.code}/collection", subject).json()
            self.assertEqual(
                [o["character"]["rarity"] for o in collection], ["basic"], subject
            )
        pool = self.get(f"/servers/{self.code}/pool").json()
        self.assertEqual(len(pool), 10, "the rarer ones join the pool")

    def test_the_setup_launches_when_the_time_is_up(self) -> None:
        self.draw_all(self.code, ADMIN)
        self.rewind(301)
        server = self.server()
        self.assertEqual(server["phase"], "running")
        pool = self.get(f"/servers/{self.code}/pool").json()
        self.assertEqual(len(pool), 2, "only what was drawn in time")
        assignment = self.assignments(self.code, FRIEND_SUBJECTS[0]).json()[0]
        late = self.client.put(
            f"/servers/{self.code}/assignments/{assignment['id']}/drawing",
            json={"title": "Late", "sketch": SKETCH},
            headers=bearer(make_token(FRIEND_SUBJECTS[0])),
        )
        self.assertEqual(late.status_code, 409)
        self.assertEqual(self.today()["day"], 1)


class SpeedDayTests(SpeedTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.launch()

    def test_days_follow_on_their_timers_until_the_session_is_over(self) -> None:
        today = self.today()
        self.assertEqual(today["day"], 1)
        self.assertAlmostEqual(
            (_parse(today["ends_at"]) - datetime.now(UTC)).total_seconds(),
            SPEED_DAY_SECONDS[0],
            delta=5,
        )
        self.rewind(SPEED_DAY_SECONDS[0] + 1)
        self.assertEqual(self.today()["day"], 2)
        self.rewind(sum(SPEED_DAY_SECONDS[1:]))
        today = self.today()
        self.assertEqual((today["day"], today["ends_at"]), (7, None))
        self.assertEqual(self.server()["phase"], "finished")

    def test_a_day_ends_early_once_everyone_is_done(self) -> None:
        # Day 1 only has the prompts.
        self.write_prompts()
        today = self.today()
        self.assertEqual(today["day"], 2, "everyone wrote theirs")
        self.assertAlmostEqual(
            (_parse(today["ends_at"]) - datetime.now(UTC)).total_seconds(),
            SPEED_DAY_SECONDS[1],
            delta=5,
        )
        # Day 2: whoever ended their day counts as done too.
        for subject in PLAYERS[:-1]:
            self.assertEqual(self.post("today/end", subject).status_code, 200)
        self.assertEqual(self.today()["day"], 2, "one is still drawing")
        self.post("today/end", PLAYERS[-1])
        self.assertEqual(self.today()["day"], 3)

    def test_prompts_are_written_on_the_first_three_days_only(self) -> None:
        for day in range(1, 4):
            today = self.today()
            self.assertEqual(today["day"], day)
            self.assertIsNotNone(today["prompt"])
            self.assertEqual(self.post("days/next").status_code, 200)
        today = self.today()
        self.assertEqual(today["day"], 4)
        self.assertIsNone(today["prompt"])
        response = self.post(
            "today/prompt", json={"title": "Too late", "subject_position": 1}
        )
        self.assertEqual(response.status_code, 409)
        self.assertIsNotNone(today["to_draw"], "day 3's prompts are drawn today")
        self.post("days/next")
        self.assertIsNone(self.today()["to_draw"], "nothing to draw on day 5")

    def test_only_the_admin_skips_ahead(self) -> None:
        self.assertEqual(self.post("days/next", FRIEND_SUBJECTS[0]).status_code, 403)
        self.assertEqual(self.post("days/next").json()["day"], 2)
        for _ in range(6):
            self.post("days/next")
        self.assertEqual(self.today()["day"], 7, "it stops when it's over")

    def test_speed_sessions_have_no_weekly_finale(self) -> None:
        for _ in range(6):
            self.post("days/next")
        self.assertIsNone(self.today()["weekly_hero"])
        ranking = self.get(f"/servers/{self.code}/ranking")
        self.assertIsNone(ranking.json())


class SpeedCleanupTests(SpeedTestCase):
    def test_speed_sessions_older_than_a_day_are_cleaned_up(self) -> None:
        self.launch()
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            server.created_at = datetime.now(UTC) - timedelta(days=2)
            session.commit()
        response = self.client.post(
            "/manage/servers/cleanup",
            headers=bearer(make_token(permissions=["read:api", "manage:servers"])),
        )
        self.assertEqual(response.json(), {"deleted": [self.code]})
        with self.session_factory() as session:
            self.assertEqual(session.scalars(select(Character)).all(), [])


class TestSessionTests(LaunchTestCase):
    def test_only_server_admins_create_test_sessions(self) -> None:
        response = self.client.post(
            "/servers",
            json={"other_names": ["Sam", "Robin", "Kim", "Jo"], "is_test": True},
            headers=bearer(make_token(ADMIN)),
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"], "Missing permission manage:servers")
        self.assertEqual(self.create(is_test=True).status_code, 201)
