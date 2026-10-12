from datetime import UTC, datetime

from sqlalchemy import select

from app import days
from app.models import PremadeTitle, Server, ThemeHint
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_launch import LaunchTestCase
from tests.test_setup import ADMIN, FRIEND_SUBJECTS

SAM = FRIEND_SUBJECTS[0]

# A Monday, so the test session's day 1 is a forest day and day 2 a beach
# day. Prompts are written for the theme of the day their heroes are picked,
# two days later: on Monday for Wednesday's volcano, on Tuesday for Thursday.
MONDAY = datetime(2026, 10, 5, 9, tzinfo=UTC)
SEEDED = datetime(2026, 1, 1, tzinfo=UTC)
HINTS = {"volcano": ["a sauna regular", "a toast burner"], "snow": ["a freezer fan"]}
TITLES = {"volcano": ["Lord of the Top Bench", "The Toast Incinerator"]}


class TodayTestCase(LaunchTestCase):
    """A launched test session with Alex and Sam."""

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
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            server.launched_at = MONDAY
            for theme, texts in HINTS.items():
                session.add_all(
                    ThemeHint(theme=theme, text=t, created_at=SEEDED) for t in texts
                )
            for theme, titles in TITLES.items():
                session.add_all(
                    PremadeTitle(theme=theme, title=t, created_at=SEEDED)
                    for t in titles
                )
            session.commit()

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


class TodayTests(TodayTestCase):
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

    def prompt(self, title: str, subject_position: int, subject: str = ADMIN):
        return self.post(
            "today/prompt",
            subject,
            json={"title": title, "subject_position": subject_position},
        )

    def test_a_prompt_is_written_once_for_anyone_but_yourself(self) -> None:
        self.assertIsNone(self.today()["prompt"]["subject_position"])
        for position in (0, 99):
            response = self.prompt("The Owl King", position)
            self.assertEqual(response.status_code, 422, position)
        response = self.prompt(" The Owl King ", 2)
        self.assertEqual(response.status_code, 200, response.text)
        written = response.json()["prompt"]
        self.assertEqual(
            (written["title"], written["subject_position"]), ("The Owl King", 2)
        )
        again = self.prompt("Another", 3)
        self.assertEqual(again.status_code, 409)
        self.assertEqual(again.json()["detail"], "You wrote today's prompt already")
        # Several players may choose the same person, even someone who
        # hasn't joined, or the player who draws it.
        self.assertEqual(self.prompt("Owl Two", 2, SAM).status_code, 200)

    def test_the_next_player_draws_the_prompt_or_a_premade_one(self) -> None:
        written = self.prompt("The Owl King", 1).json()
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
        self.assertEqual(sam["to_draw"]["hint"], written["prompt"]["hint"])
        self.assertIn(sam["to_draw"]["hint"], HINTS["volcano"])
        self.assertFalse(sam["to_draw"]["premade"])
        self.assertEqual(sam["to_draw"]["theme"], "volcano")

        # Sam wrote nothing, so Alex draws a premade volcano prompt of
        # someone other than Sam.
        alex = self.today()["to_draw"]
        self.assertTrue(alex["premade"])
        self.assertEqual(alex["author_position"], 1)
        self.assertIn(alex["title"], TITLES["volcano"])
        self.assertEqual(alex["theme"], "volcano")
        self.assertNotEqual(alex["subject_position"], 1)
        self.assertIsNone(alex["hint"], "nobody got a description for it")

    def test_a_challenger_earns_a_pull_but_stays_out_of_the_pool(self) -> None:
        self.post("days/next")
        response = self.draw(SAM)
        self.assertEqual(response.status_code, 200, response.text)
        challenger = response.json()["to_draw"]["challenger"]
        self.assertEqual(
            (challenger["rarity"], challenger["prompt"], challenger["day"]),
            ("hero", "challenger", 2),
        )
        self.assertEqual(challenger["theme"], "volcano")
        pool = [c["id"] for c in self.get(f"/servers/{self.code}/pool").json()]
        self.assertNotIn(challenger["id"], pool)
        [listed] = self.get(f"/servers/{self.code}/challengers", SAM).json()
        self.assertEqual(listed["character"]["id"], challenger["id"])
        self.assertEqual((listed["fights"], listed["wins"]), (0, 0))
        self.assertEqual(
            self.get(f"/servers/{self.code}/challengers").json(),
            [],
            "the others haven't encountered it yet",
        )
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


class HurryTests(TodayTestCase):
    def test_a_free_hurry_a_day_cuts_the_targets_drawing_time(self) -> None:
        self.assertIsNone(self.today()["hurry_sent_to"])
        response = self.post("today/hurry", json={"target_position": 1})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["hurry_sent_to"], 1)
        self.assertIsNone(response.json()["incoming_hurry"])

        incoming = self.today(SAM)["incoming_hurry"]
        self.assertEqual((incoming["by_position"], incoming["cut_seconds"]), (0, 30))
        self.assertTrue(0.25 <= incoming["at_fraction"] <= 0.6)

        again = self.post("today/hurry", json={"target_position": 1})
        self.assertEqual(again.status_code, 409)
        self.assertEqual(again.json()["detail"], "You sent today's hurry already")

        self.post("days/next")
        self.assertIsNone(self.today()["hurry_sent_to"], "a new day, a new hurry")
        self.assertIsNone(self.today(SAM)["incoming_hurry"])

    def test_only_other_players_who_joined(self) -> None:
        self.assertEqual(
            self.post("today/hurry", json={"target_position": 0}).status_code, 422
        )
        self.assertEqual(
            self.post("today/hurry", json={"target_position": 3}).status_code, 404
        )


class ThemeTests(TodayTestCase):
    def test_each_player_gets_a_hint_of_the_challengers_theme(self) -> None:
        monday = self.today()
        alex, sam = monday["prompt"], self.today(SAM)["prompt"]
        self.assertEqual((monday["theme"], alex["theme"]), ("forest", "volcano"))
        self.assertIn(alex["hint"], HINTS["volcano"])
        self.assertIn(sam["hint"], HINTS["volcano"])
        self.assertEqual(self.today()["prompt"], alex, "the hint stays the same")

        self.post("days/next")
        tuesday = self.today()
        self.assertEqual(
            (tuesday["theme"], tuesday["prompt"]["theme"]), ("beach", "snow")
        )
        self.assertEqual(tuesday["prompt"]["hint"], "a freezer fan")

        # Friday's jungle has no hints, and nobody wrote a title on Tuesday,
        # for Thursday's snow, which has no premade titles either.
        self.post("days/next")
        wednesday = self.today()
        self.assertEqual(wednesday["theme"], "volcano")
        self.assertEqual(wednesday["prompt"]["theme"], "jungle")
        self.assertIsNone(wednesday["prompt"]["hint"])
        self.assertEqual(wednesday["to_draw"]["title"], days.FALLBACK_TITLE)
        self.assertEqual(wednesday["to_draw"]["theme"], "snow")

    def test_every_player_gets_another_hint_and_a_new_one_next_week(self) -> None:
        monday = {s: self.today(s)["prompt"]["hint"] for s in (ADMIN, SAM)}
        self.assertEqual(set(monday.values()), set(HINTS["volcano"]))
        for _ in range(7):
            self.post("days/next")
        next_monday = {s: self.today(s)["prompt"] for s in (ADMIN, SAM)}
        self.assertEqual(next_monday[ADMIN]["theme"], "volcano")
        for subject in (ADMIN, SAM):
            self.assertIn(next_monday[subject]["hint"], HINTS["volcano"])
            self.assertNotEqual(next_monday[subject]["hint"], monday[subject])

    def test_new_hints_count_from_the_day_after_they_were_added(self) -> None:
        before = self.today()["prompt"]["hint"]
        with self.session_factory() as session:
            # Added now, long after the test session's Monday began.
            session.add(ThemeHint(theme="volcano", text="a brand new hint"))
            session.commit()
        self.assertEqual(self.today()["prompt"]["hint"], before)
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            self.assertNotIn(
                "a brand new hint",
                {
                    days.prompt_hint(session, server, 1, s)
                    for s in days.active_seats(server)
                },
            )

    def test_the_theme_follows_the_weekday(self) -> None:
        sunday = Server(launched_at=datetime(2026, 10, 11, 23, 59, tzinfo=UTC))
        self.assertEqual(days.theme_of(sunday, 1).value, "castle")
        self.assertEqual(days.theme_of(sunday, 2).value, "forest")
        self.assertEqual(days.theme_of(sunday, 6).value, "jungle")
