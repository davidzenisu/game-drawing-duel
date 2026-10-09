from sqlalchemy import func, select

from app.models import Character, Server, ServerSeat, SetupAssignment
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_setup import ADMIN, FRIEND_SUBJECTS, SetupTestCase


class CancelTests(SetupTestCase):
    def cancel(self, code: str, subject: str = ADMIN):
        return self.client.delete(
            f"/servers/{code}", headers=bearer(make_token(subject))
        )

    def count(self, model) -> int:
        with self.session_factory() as session:
            return session.scalar(select(func.count()).select_from(model))

    def test_the_admin_cancels_in_the_lobby(self) -> None:
        code = self.create().json()["code"]
        response = self.cancel(code)
        self.assertEqual(response.status_code, 204, response.text)
        self.assertEqual(
            self.client.get(
                f"/servers/{code}", headers=bearer(make_token(ADMIN))
            ).status_code,
            404,
        )
        self.assertEqual((self.count(Server), self.count(ServerSeat)), (0, 0))

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
        self.assertEqual(self.files.files, {})
        for model in (Server, ServerSeat, SetupAssignment, Character):
            self.assertEqual(self.count(model), 0, model.__name__)
        mine = self.client.get("/servers/mine", headers=bearer(make_token(ADMIN)))
        self.assertEqual(mine.json(), [])

    def test_only_players_of_the_server_cancel_it(self) -> None:
        code = self.create().json()["code"]
        self.sign_up("auth0|stranger", "Pat")
        response = self.cancel(code, "auth0|stranger")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.count(Server), 1)
        self.assertEqual(self.cancel("999999").status_code, 404)
