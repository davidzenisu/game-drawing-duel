from collections import Counter
from datetime import UTC, datetime

from app import rules
from app.models import SetupHint
from tests.helpers import bearer, make_token
from tests.test_servers import ADMIN, FRIENDS, ServerTestCase

FRIEND_SUBJECTS = [f"auth0|{name.lower()}" for name in FRIENDS]


class SetupTestCase(ServerTestCase):
    """Helpers to start the setup and read the assignments."""

    def join_everyone(self, code: str) -> None:
        for position, (name, subject) in enumerate(zip(FRIENDS, FRIEND_SUBJECTS), 1):
            self.sign_up(subject, name)
            self.assertEqual(self.claim(code, position, subject).status_code, 200)

    def start(self, code: str, subject: str = ADMIN):
        return self.client.post(
            f"/servers/{code}/setup", headers=bearer(make_token(subject))
        )

    def assignments(self, code: str, subject: str = ADMIN):
        return self.client.get(
            f"/servers/{code}/assignments", headers=bearer(make_token(subject))
        )


class SetupTests(SetupTestCase):
    def test_regular_servers_start_once_everyone_joined(self) -> None:
        code = self.create().json()["code"]
        response = self.start(code)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "Not everyone joined yet")
        self.join_everyone(code)
        response = self.start(code)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["phase"], "setup")
        self.assertEqual(self.start(code).json()["detail"], "The setup already started")

    def test_only_the_admin_starts_the_setup(self) -> None:
        code = self.create().json()["code"]
        self.join_everyone(code)
        response = self.start(code, FRIEND_SUBJECTS[0])
        self.assertEqual(response.status_code, 403)
        self.assertEqual(
            response.json()["detail"], "Only the admin can start the setup"
        )

    def test_everyone_draws_the_planned_prompts_of_the_other_players(self) -> None:
        code = self.create().json()["code"]
        self.join_everyone(code)
        self.start(code)
        players = len(FRIENDS) + 1
        for position, subject in enumerate([ADMIN, *FRIEND_SUBJECTS]):
            response = self.assignments(code, subject)
            self.assertEqual(response.status_code, 200, response.text)
            planned = rules.assignments_for(players, position)
            self.assertEqual(
                [(a["prompt"], a["subject_position"]) for a in response.json()],
                [(p.prompt.value, p.subject) for p in planned],
            )

    def test_the_alter_is_based_on_the_basic(self) -> None:
        code = self.create().json()["code"]
        self.join_everyone(code)
        self.start(code)
        by_prompt = {a["prompt"]: a for a in self.assignments(code).json()}
        self.assertEqual(by_prompt["alter"]["based_on"], by_prompt["basic"]["id"])
        self.assertIsNone(by_prompt["basic"]["based_on"])

    def test_every_drawing_gets_a_starter_prompt_of_its_type(self) -> None:
        with self.session_factory() as session:
            session.add_all(
                [SetupHint(prompt="basic", text=f"basic {n}") for n in range(3)]
                + [SetupHint(prompt="knight", text=f"knight {n}") for n in range(9)]
                + [
                    SetupHint(
                        prompt="knight",
                        text="retired",
                        retired_at=datetime(2026, 1, 1, tzinfo=UTC),
                    )
                ]
            )
            session.commit()
        code = self.create().json()["code"]
        self.join_everyone(code)
        self.start(code)
        drawn = [
            a
            for subject in [ADMIN, *FRIEND_SUBJECTS]
            for a in self.assignments(code, subject).json()
        ]
        by_prompt: dict[str, Counter] = {}
        for a in drawn:
            by_prompt.setdefault(a["prompt"], Counter())[a["hint"]] += 1
        players = len(FRIENDS) + 1
        # Three basic prompts for every player's basic: each used, none twice
        # before all of them were.
        self.assertEqual(set(by_prompt["basic"]), {"basic 0", "basic 1", "basic 2"})
        self.assertLessEqual(
            max(by_prompt["basic"].values()) - min(by_prompt["basic"].values()), 1
        )
        # Enough knight prompts for everyone: all different, none retired.
        self.assertEqual(sum(by_prompt["knight"].values()), players)
        self.assertEqual(set(by_prompt["knight"].values()), {1})
        self.assertNotIn("retired", by_prompt["knight"])
        # Types without starter prompts get none.
        self.assertEqual(set(by_prompt["legend"]), {None})

    def test_assignments_need_a_seat_and_a_started_setup(self) -> None:
        code = self.create().json()["code"]
        response = self.assignments(code)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "The setup hasn't started yet")
        self.sign_up("auth0|stranger", "Pat")
        response = self.assignments(code, "auth0|stranger")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"], "You haven't joined this server")

    def assert_test_assignments(self, code: str, subject: str, position: int) -> None:
        """The short setup, of different players other than yourself."""
        assignments = self.assignments(code, subject).json()
        self.assertEqual(
            [a["prompt"] for a in assignments], ["basic", "knight", "legend"]
        )
        subjects = [a["subject_position"] for a in assignments]
        self.assertEqual(len(set(subjects)), 3)
        self.assertNotIn(position, subjects)
        self.assertTrue(set(subjects) <= set(range(len(FRIENDS) + 1)))

    def test_test_sessions_start_with_whoever_joined(self) -> None:
        code = self.create(is_test=True).json()["code"]
        self.sign_up(FRIEND_SUBJECTS[0], FRIENDS[0])
        self.claim(code, 1, FRIEND_SUBJECTS[0])
        response = self.start(code)
        self.assertEqual(response.status_code, 200, response.text)
        self.assert_test_assignments(code, ADMIN, 0)
        self.assert_test_assignments(code, FRIEND_SUBJECTS[0], 1)
        stranger = self.assignments(code, FRIEND_SUBJECTS[1])
        self.assertEqual(stranger.status_code, 403, "only who joined draws")

    def test_alone_in_a_test_session_you_draw_the_others(self) -> None:
        code = self.create(is_test=True).json()["code"]
        self.start(code)
        self.assert_test_assignments(code, ADMIN, 0)

    def test_late_joiners_of_a_test_session_draw_along(self) -> None:
        code = self.create(is_test=True).json()["code"]
        self.start(code)
        before = self.assignments(code).json()
        self.sign_up(FRIEND_SUBJECTS[2], FRIENDS[2])
        joined = self.claim(code, 3, FRIEND_SUBJECTS[2])
        self.assertEqual(joined.status_code, 200, joined.text)
        self.assertEqual(joined.json()["phase"], "setup")
        self.assert_test_assignments(code, FRIEND_SUBJECTS[2], 3)
        # The admin keeps the assignments they started with.
        self.assertEqual(self.assignments(code).json(), before)
