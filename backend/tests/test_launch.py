from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_setup import ADMIN, FRIEND_SUBJECTS, SetupTestCase

EVERYONE = [ADMIN, *FRIEND_SUBJECTS]


class LaunchTestCase(SetupTestCase):
    """Helpers to draw everything, finish the setup and read the game."""

    def draw_all(self, code: str, subject: str) -> None:
        for assignment in self.assignments(code, subject).json():
            response = self.client.put(
                f"/servers/{code}/assignments/{assignment['id']}/drawing",
                json={"title": assignment["prompt"], "sketch": SKETCH},
                headers=bearer(make_token(subject)),
            )
            self.assertEqual(response.status_code, 200, response.text)

    def finish(self, code: str, subject: str = ADMIN):
        return self.client.post(
            f"/servers/{code}/setup/done", headers=bearer(make_token(subject))
        )

    def get(self, path: str, subject: str = ADMIN):
        return self.client.get(path, headers=bearer(make_token(subject)))

    def started_server(self) -> str:
        code = self.create().json()["code"]
        self.join_everyone(code)
        self.start(code)
        return code


class LaunchTests(LaunchTestCase):
    def test_the_last_player_to_finish_launches_the_game(self) -> None:
        code = self.started_server()
        for subject in EVERYONE:
            self.draw_all(code, subject)
        for subject in EVERYONE[:-1]:
            response = self.finish(code, subject)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.json()["phase"], "setup")
        seats = self.get(f"/servers/{code}").json()["seats"]
        self.assertEqual([s["setup_done"] for s in seats], [True] * 4 + [False])

        response = self.finish(code, EVERYONE[-1])
        self.assertEqual(response.json()["phase"], "running")
        self.assertEqual(self.get(f"/servers/{code}").json()["phase"], "running")

    def test_finishing_needs_every_drawing(self) -> None:
        code = self.started_server()
        response = self.finish(code)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "Finish all your drawings first")

    def test_finished_drawings_are_final(self) -> None:
        code = self.started_server()
        self.draw_all(code, ADMIN)
        self.finish(code)
        self.assertEqual(self.finish(code).status_code, 200, "finishing twice is fine")
        basic = self.assignments(code).json()[0]
        response = self.client.put(
            f"/servers/{code}/assignments/{basic['id']}/drawing",
            json={"title": "Again", "sketch": SKETCH},
            headers=bearer(make_token(ADMIN)),
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "You already finished your setup")

    def test_the_pool_and_your_collection_after_the_launch(self) -> None:
        code = self.started_server()
        response = self.get(f"/servers/{code}/pool")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "The game hasn't launched yet")
        for subject in EVERYONE:
            self.draw_all(code, subject)
            self.finish(code, subject)

        pool = self.get(f"/servers/{code}/pool").json()
        self.assertEqual(len(pool), 30, "~30 characters at launch")
        collection = self.get(f"/servers/{code}/collection", FRIEND_SUBJECTS[0]).json()
        self.assertEqual(len(collection), 6)
        self.assertEqual({c["character"]["artist_position"] for c in collection}, {1})
        self.assertEqual({c["copies"] for c in collection}, {1})
        self.sign_up("auth0|stranger", "Pat")
        self.assertEqual(
            self.get(f"/servers/{code}/pool", "auth0|stranger").status_code, 403
        )

    def test_a_launched_game_cannot_be_cancelled(self) -> None:
        code = self.create(is_test=True).json()["code"]
        self.start(code)
        self.draw_all(code, ADMIN)
        self.assertEqual(self.finish(code).json()["phase"], "running")
        response = self.client.delete(
            f"/servers/{code}", headers=bearer(make_token(ADMIN))
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "The game already launched")
        self.sign_up(FRIEND_SUBJECTS[0], "Sam")
        self.assertEqual(self.claim(code, 1, FRIEND_SUBJECTS[0]).status_code, 409)

    def test_a_test_session_waits_for_late_joiners(self) -> None:
        code = self.create(is_test=True).json()["code"]
        self.start(code)
        self.sign_up(FRIEND_SUBJECTS[0], "Sam")
        self.claim(code, 1, FRIEND_SUBJECTS[0])
        self.draw_all(code, ADMIN)
        self.assertEqual(self.finish(code).json()["phase"], "setup")
        self.draw_all(code, FRIEND_SUBJECTS[0])
        self.assertEqual(
            self.finish(code, FRIEND_SUBJECTS[0]).json()["phase"], "running"
        )
        self.assertEqual(len(self.get(f"/servers/{code}/pool").json()), 6)
