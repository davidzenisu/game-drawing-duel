from datetime import timedelta

from sqlalchemy import select

from app.database import utc_now
from app.main import app
from app.models import Server, ServerSeat
from tests.helpers import bearer, make_token
from tests.test_cancel import CancelTestMixin
from tests.test_fights import FightTestCase
from tests.test_setup import ADMIN

SERVER_ADMIN = ["read:api", "manage:servers"]


class CleanupTests(CancelTestMixin, FightTestCase):
    def clean_up(self, permissions=SERVER_ADMIN):
        return self.client.post(
            "/manage/servers/cleanup",
            headers=bearer(make_token(ADMIN, permissions=permissions)),
        )

    def age(self, code: str, days: int) -> None:
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == code))
            server.created_at = utc_now() - timedelta(days=days)
            session.commit()

    def test_no_route_lives_under_admin(self) -> None:
        # The Azure Functions host answers every /admin path itself, with a
        # 404 when deployed.
        paths = list(app.openapi()["paths"])
        self.assertIn("/manage/servers/cleanup", paths)
        self.assertEqual([p for p in paths if p.startswith("/admin")], [])

    def test_only_server_admins_clean_up(self) -> None:
        response = self.clean_up(permissions=["read:api"])
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"], "Missing permission manage:servers")

    def test_test_sessions_older_than_a_day_are_deleted_with_their_data(self) -> None:
        # The fight test case played a test session to day 3, with drawings.
        self.assertTrue(self.files.files)
        self.age(self.code, days=2)
        fresh = self.create(is_test=True).json()["code"]
        regular = self.create().json()["code"]
        self.age(regular, days=30)

        response = self.clean_up()
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json(), {"deleted": [self.code]})
        self.assert_game_data_deleted()
        with self.session_factory() as session:
            left = set(session.scalars(select(Server.code)))
            seats = session.scalars(select(ServerSeat.server_id).distinct()).all()
        self.assertEqual(left, {fresh, regular})
        self.assertEqual(len(seats), 2, "the deleted server's seats go too")
        self.assertEqual(self.clean_up().json(), {"deleted": []})
