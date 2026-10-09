from app import rules
from tests.helpers import bearer, make_token
from tests.test_servers import ADMIN, FRIENDS, ServerTestCase

FRIEND_SUBJECTS = [f"auth0|{name.lower()}" for name in FRIENDS]


class SetupTests(ServerTestCase):
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

    def test_assignments_need_a_seat_and_a_started_setup(self) -> None:
        code = self.create().json()["code"]
        response = self.assignments(code)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "The setup hasn't started yet")
        self.sign_up("auth0|stranger", "Pat")
        response = self.assignments(code, "auth0|stranger")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"], "You haven't joined this server")

    def test_test_sessions_start_with_whoever_joined(self) -> None:
        code = self.create(is_test=True).json()["code"]
        self.sign_up(FRIEND_SUBJECTS[0], FRIENDS[0])
        self.claim(code, 1, FRIEND_SUBJECTS[0])
        response = self.start(code)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(
            [
                (a["prompt"], a["subject_position"])
                for a in self.assignments(code).json()
            ],
            [("basic", 1), ("knight", 1), ("legend", 1)],
        )
        friend = self.assignments(code, FRIEND_SUBJECTS[0]).json()
        self.assertEqual([a["subject_position"] for a in friend], [0, 0, 0])

    def test_alone_in_a_test_session_you_draw_yourself(self) -> None:
        code = self.create(is_test=True).json()["code"]
        self.start(code)
        self.assertEqual(
            [
                (a["prompt"], a["subject_position"])
                for a in self.assignments(code).json()
            ],
            [("basic", 0), ("knight", 0), ("legend", 0)],
        )

    def test_late_joiners_of_a_test_session_draw_along(self) -> None:
        code = self.create(is_test=True).json()["code"]
        self.start(code)
        self.sign_up(FRIEND_SUBJECTS[2], FRIENDS[2])
        joined = self.claim(code, 3, FRIEND_SUBJECTS[2])
        self.assertEqual(joined.status_code, 200, joined.text)
        self.assertEqual(joined.json()["phase"], "setup")
        late = self.assignments(code, FRIEND_SUBJECTS[2]).json()
        self.assertEqual([a["subject_position"] for a in late], [0, 0, 0])
        # The admin keeps the assignments they started with.
        admin = self.assignments(code).json()
        self.assertEqual([a["subject_position"] for a in admin], [0, 0, 0])
