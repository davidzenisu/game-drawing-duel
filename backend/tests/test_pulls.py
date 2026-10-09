from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app import pulls
from app.models import Pull, ServerSeat
from tests.helpers import bearer, make_token
from tests.test_launch import LaunchTestCase
from tests.test_setup import ADMIN


class PullTestCase(LaunchTestCase):
    """A launched test session played alone, with helpers to pull."""

    def setUp(self) -> None:
        super().setUp()
        # A test session played alone: Basic, Knight and Legend of others.
        self.code = self.create(is_test=True).json()["code"]
        self.start(self.code)
        self.draw_all(self.code, ADMIN)
        self.finish(self.code)

    def gacha(self):
        return self.get(f"/servers/{self.code}/gacha").json()

    def pull(self, count: int):
        return self.client.post(
            f"/servers/{self.code}/pulls",
            json={"count": count},
            headers=bearer(make_token(ADMIN)),
        )


class PullTests(PullTestCase):
    def test_the_launch_awards_ten_pulls(self) -> None:
        self.assertEqual(
            self.gacha(),
            {
                "tickets": 10,
                "total_pulls": 0,
                "pulls_until_legend": 50,
                "beginner_pulls_left": 10,
            },
        )

    def test_a_pull_spends_one_grant_on_a_character_of_the_pool(self) -> None:
        response = self.pull(1)
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        outcome = body["outcomes"][0]
        pool = {c["id"] for c in self.get(f"/servers/{self.code}/pool").json()}
        self.assertIn(outcome["character"]["id"], pool)
        # You own your setup drawings already.
        self.assertEqual((outcome["is_new"], outcome["copies"]), (False, 2))
        self.assertEqual(body["gacha"]["tickets"], 9)
        self.assertEqual(body["gacha"]["total_pulls"], 1)

        collection = {
            c["character"]["id"]: c["copies"]
            for c in self.get(f"/servers/{self.code}/collection").json()
        }
        self.assertEqual(collection[outcome["character"]["id"]], 2)

    def test_the_beginner_window_guarantees_a_rare_character(self) -> None:
        outcomes = self.pull(10).json()["outcomes"]
        self.assertEqual(len(outcomes), 10)
        # No heroes exist yet, so the guarantee looks upwards to a legend.
        self.assertIn("legend", [o["character"]["rarity"] for o in outcomes])
        self.assertEqual(self.gacha()["tickets"], 0)

    def test_pulls_need_tickets(self) -> None:
        self.pull(8)
        response = self.pull(3)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "Not enough pulls")
        self.assertEqual(self.gacha()["tickets"], 2, "nothing was spent")
        for count in (0, 11):
            self.assertEqual(self.pull(count).status_code, 422)

    def test_the_same_reward_is_never_awarded_twice(self) -> None:
        with self.session_factory() as session:
            seat = session.scalar(select(ServerSeat).where(ServerSeat.position == 0))
            pulls.grant_launch_bonus(session, [seat])
            with self.assertRaises(IntegrityError):
                session.commit()

    def test_every_pull_is_recorded_in_order(self) -> None:
        self.pull(4)
        self.pull(3)
        with self.session_factory() as session:
            numbers = session.scalars(select(Pull.number).order_by(Pull.number)).all()
            self.assertEqual(numbers, list(range(1, 8)))
            self.assertEqual(
                session.scalar(select(func.count(func.distinct(Pull.grant_id)))), 7
            )

    def test_pulls_wait_for_the_launch(self) -> None:
        code = self.create(is_test=True).json()["code"]
        response = self.get(f"/servers/{code}/gacha")
        self.assertEqual(response.status_code, 409)
