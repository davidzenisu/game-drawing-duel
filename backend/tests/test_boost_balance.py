from datetime import UTC, date, datetime
from unittest.mock import patch

from sqlalchemy import delete, func, select, update

from app import rules
from app.models import Boost, Fight, Server
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_fights import ADMIN, PLAYERS, FightTestCase


class BoostBalanceTests(FightTestCase):
    """The week before's fights change the week's boost stars."""

    def setUp(self) -> None:
        super().setUp()
        # Day 1 is a Monday: days 1 to 7 are a week, day 8 starts the next.
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            server.launched_at = datetime(2026, 10, 5, 9, tzinfo=UTC)
            session.commit()
        # The balance from the launch week on, unless a test says otherwise.
        self.balance_from(date(2026, 10, 5))

    def balance_from(self, monday: date) -> None:
        balance_from = patch("app.rules.BALANCE_FROM", monday)
        balance_from.start()
        self.addCleanup(balance_from.stop)

    def next_day(self):
        # Everyone draws a challenger, so there's one to boost and fight.
        for subject in PLAYERS:
            self.client.put(
                f"/servers/{self.code}/today/challenger",
                json={"sketch": SKETCH},
                headers=bearer(make_token(subject)),
            )
        return super().next_day()

    def to_day(self, day: int) -> None:
        with self.without_rest():
            while self.today()["day"] < day:
                self.next_day()

    def set_results(self, first: int, last: int, fighters_win: bool) -> int:
        """Decides every fight from `first` to `last` for one side; returns
        how many there are."""
        with self.session_factory() as session:
            session.execute(
                update(Fight)
                .where(Fight.day >= first, Fight.day <= last)
                .values(fighters_win=fighters_win)
            )
            session.commit()
            return session.scalar(
                select(func.count())
                .select_from(Fight)
                .where(Fight.day >= first, Fight.day <= last)
            )

    def week_stats(self) -> dict:
        return self.get(f"/servers/{self.code}/player-stats").json()

    def test_the_first_week_gives_the_base_stars(self) -> None:
        step = self.today()["boost"]
        self.assertEqual((step["stars"], step["max_per_challenger"]), (3, 3))
        self.assertIsNone(step["balance"])
        self.assertFalse(step["next_week"])
        self.assertIsNone(self.week_stats()["boost_balance"])

    def test_heroes_winning_most_fights_give_more_stars_from_sunday(self) -> None:
        self.to_day(6)
        self.assertEqual(self.today()["boost"]["stars"], 3, "Saturday's are this week's")
        self.to_day(7)
        fights = self.set_results(1, 6, True)
        self.assertGreaterEqual(fights, rules.BOOST_BALANCE_MIN_FIGHTS)
        step = self.today()["boost"]
        self.assertEqual((step["stars"], step["max_per_challenger"]), (5, 5))
        self.assertTrue(step["next_week"], "Sunday's challengers are fought on Monday")
        self.assertEqual(
            step["balance"],
            {
                "from_day": 1,
                "to_day": 6,
                "fights": fights,
                "hero_wins": fights,
                "min_fights": rules.BOOST_BALANCE_MIN_FIGHTS,
                "previous_stars": 3,
                "step": 2,
                "stars": 5,
            },
        )
        self.assertIsNone(self.week_stats()["boost_balance"], "this week's: the first")

        challenger = step["targets"][0]["challenger"]["id"]
        response = self.boost({challenger: 5})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.boost({challenger: 6}).status_code, 409)

        self.next_day()
        self.set_results(7, 7, False)
        monday = self.today()["boost"]
        self.assertEqual(monday["balance"], step["balance"], "Sunday's fights don't count")
        self.assertFalse(monday["next_week"])
        self.assertEqual(self.week_stats()["boost_balance"], step["balance"])

    def test_chance_spreads_the_weeks_stars(self) -> None:
        self.to_day(7)
        self.set_results(1, 6, True)
        self.next_day()
        with self.session_factory() as session:
            spread = session.scalars(
                select(func.sum(Boost.stars))
                .where(Boost.day == 7)
                .group_by(Boost.booster_seat_id)
            ).all()
        self.assertEqual(set(spread), {5}, "next week's stars, all of them")

    def test_challengers_winning_most_fights_never_go_below_the_minimum(
        self,
    ) -> None:
        self.to_day(7)
        self.set_results(1, 6, False)
        balance = self.today()["boost"]["balance"]
        self.assertEqual(
            (balance["previous_stars"], balance["step"], balance["stars"]), (3, -2, 3)
        )

    def test_too_few_fights_change_nothing(self) -> None:
        self.to_day(7)
        self.set_results(1, 6, True)
        with self.session_factory() as session:
            session.execute(delete(Fight).where(Fight.day < 6))
            session.commit()
        balance = self.today()["boost"]["balance"]
        self.assertLess(balance["fights"], rules.BOOST_BALANCE_MIN_FIGHTS)
        self.assertEqual((balance["step"], balance["stars"]), (0, 3))

    def test_weeks_stack_up_to_the_maximum(self) -> None:
        self.to_day(14)
        self.set_results(1, 6, True)
        self.set_results(8, 13, True)
        balance = self.today(ADMIN)["boost"]["balance"]
        self.assertEqual(
            (balance["from_day"], balance["previous_stars"], balance["step"]),
            (8, 5, 2),
        )
        self.assertEqual(balance["stars"], 6, "never more than the maximum")

        self.set_results(8, 13, False)
        balance = self.today(ADMIN)["boost"]["balance"]
        self.assertEqual((balance["previous_stars"], balance["stars"]), (5, 3))

    def test_the_weeks_before_the_balance_keep_the_base_stars(self) -> None:
        # Running servers switch between two weeks: from day 15's on.
        self.balance_from(date(2026, 10, 19))
        self.to_day(8)
        self.set_results(1, 7, True)
        step = self.today()["boost"]
        self.assertEqual((step["stars"], step["balance"]), (3, None))
        self.assertIsNone(self.week_stats()["boost_balance"])
        self.assertEqual(self.boost({step["targets"][0]["challenger"]["id"]: 4}).status_code, 409)

        self.to_day(14)
        self.set_results(1, 13, True)
        balance = self.today()["boost"]["balance"]
        self.assertEqual(
            (balance["previous_stars"], balance["step"], balance["stars"]),
            (3, 2, 5),
            "the first week on starts from the base stars",
        )
