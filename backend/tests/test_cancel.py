from sqlalchemy import func, select

from app.models import (
    ChallengerPrompt,
    Character,
    DayEnd,
    Fight,
    Fighter,
    Hurry,
    Pull,
    PullGrant,
    Server,
    ServerSeat,
    SetupAssignment,
    Upgrade,
    Vote,
)
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_fights import ROBIN, SAM, FightTestCase
from tests.test_setup import ADMIN, FRIEND_SUBJECTS, SetupTestCase

GAME_DATA = (
    ChallengerPrompt,
    Character,
    DayEnd,
    Fight,
    Fighter,
    Hurry,
    Pull,
    PullGrant,
    SetupAssignment,
    Upgrade,
    Vote,
)


class CancelTestMixin:
    def cancel(self, code: str, subject: str = ADMIN):
        return self.client.delete(
            f"/servers/{code}", headers=bearer(make_token(subject))
        )

    def dismiss(self, code: str, subject: str = ADMIN):
        return self.client.post(
            f"/servers/{code}/dismiss", headers=bearer(make_token(subject))
        )

    def mine(self, subject: str = ADMIN) -> list[dict]:
        return self.client.get(
            "/servers/mine", headers=bearer(make_token(subject))
        ).json()

    def count(self, model) -> int:
        with self.session_factory() as session:
            return session.scalar(select(func.count()).select_from(model))

    def assert_game_data_deleted(self) -> None:
        self.assertEqual(self.files.files, {})
        for model in GAME_DATA:
            self.assertEqual(self.count(model), 0, model.__name__)


class CancelTests(CancelTestMixin, SetupTestCase):
    def test_the_admin_cancels_in_the_lobby(self) -> None:
        code = self.create().json()["code"]
        response = self.cancel(code)
        self.assertEqual(response.status_code, 204, response.text)
        server = self.client.get(f"/servers/{code}", headers=bearer(make_token(ADMIN)))
        self.assertEqual(server.json()["phase"], "cancelled")
        self.assertEqual(server.json()["cancelled_by"], "Alex")
        self.assertEqual(self.mine(), [], "who cancelled needs no notice")
        self.assertEqual((self.count(Server), self.count(ServerSeat)), (1, 5))

    def test_a_player_dropping_out_cancels_the_setup_for_everyone(self) -> None:
        code = self.create().json()["code"]
        self.join_everyone(code)
        self.start(code)
        for subject in (ADMIN, FRIEND_SUBJECTS[0]):
            basic = self.assignments(code, subject).json()[0]
            drawn = self.client.put(
                f"/servers/{code}/assignments/{basic['id']}/drawing",
                json={"title": "Me", "sketch": SKETCH},
                headers=bearer(make_token(subject)),
            )
            self.assertEqual(drawn.status_code, 200, drawn.text)
        self.assertEqual(len(self.files.files), 2)

        response = self.cancel(code, FRIEND_SUBJECTS[1])
        self.assertEqual(response.status_code, 204, response.text)
        self.assert_game_data_deleted()

        # The others find out when they return, until they dismiss it.
        [cancelled] = self.mine()
        self.assertEqual(cancelled["phase"], "cancelled")
        self.assertEqual(cancelled["cancelled_by"], "Robin")
        self.assertEqual(self.assignments(code).status_code, 410)
        self.assertEqual(self.dismiss(code).status_code, 204)
        self.assertEqual(self.dismiss(code).status_code, 204, "dismissing again is ok")
        self.assertEqual(self.mine(), [])
        self.assertEqual(len(self.mine(FRIEND_SUBJECTS[0])), 1)

    def test_a_cancelled_server_is_cancelled_once_and_joined_by_nobody(self) -> None:
        code = self.create().json()["code"]
        self.cancel(code)
        self.assertEqual(self.cancel(code).status_code, 410)
        self.sign_up(FRIEND_SUBJECTS[0], "Sam")
        self.assertEqual(self.claim(code, 1, FRIEND_SUBJECTS[0]).status_code, 410)

    def test_only_cancelled_servers_are_dismissed(self) -> None:
        code = self.create().json()["code"]
        self.assertEqual(self.dismiss(code).status_code, 409)
        self.assertEqual(len(self.mine()), 1)

    def test_only_players_of_the_server_cancel_it(self) -> None:
        code = self.create().json()["code"]
        self.sign_up("auth0|stranger", "Pat")
        response = self.cancel(code, "auth0|stranger")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.dismiss(code, "auth0|stranger").status_code, 403)
        self.assertEqual(self.mine()[0]["phase"], "lobby")
        self.assertEqual(self.cancel("999999").status_code, 404)


class CancelRunningGameTests(CancelTestMixin, FightTestCase):
    def test_a_running_game_is_cancelled_with_all_its_data(self) -> None:
        # Day 3: fights, a hurry and an ended day on top of the setup,
        # challengers and pulls.
        self.pick(self.owned()[:2])
        self.post("today/hurry", json={"target_position": 1})
        self.post("today/end", SAM)
        self.next_day()
        for model in (Fight, Fighter, Hurry, DayEnd, PullGrant, Character):
            self.assertGreater(self.count(model), 0, model.__name__)

        response = self.cancel(self.code, ROBIN)
        self.assertEqual(response.status_code, 204, response.text)
        self.assert_game_data_deleted()
        self.assertEqual(self.mine()[0]["phase"], "cancelled")
        for path in ("today", "pool", "collection", "gacha"):
            self.assertEqual(
                self.get(f"/servers/{self.code}/{path}").status_code, 410, path
            )
