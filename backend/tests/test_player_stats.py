import uuid

from sqlalchemy import select

from app import player_stats
from app.models import Character, Fight, Server, ServerSeat
from tests.helpers import bearer, make_token
from tests.test_fights import ADMIN, PLAYERS
from tests.test_finale import FinaleTestCase
from tests.test_speed import SpeedTestCase


class PlayerStatsTests(FinaleTestCase):
    """The player stats of the week ranking, see `app/player_stats.py`.
    Day 1 is a Monday; on day 4, everyone drew a challenger on days 2 and
    3, and day 2's are fought."""

    def stats(self, period: str | None = None, subject: str = ADMIN):
        query = "" if period is None else f"?period={period}"
        response = self.get(f"/servers/{self.code}/player-stats{query}", subject)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    @staticmethod
    def stat(stats: dict, key: str) -> list[tuple[int, int, int]]:
        """A stat's ranking: (position, value, place) per player."""
        entry = next(s for s in stats["stats"] if s["key"] == key)
        return [
            (p["player_position"], p["value"], p["place"]) for p in entry["players"]
        ]

    def test_every_stat_ranks_every_player(self) -> None:
        written = self.post(
            "today/prompt", ADMIN, {"subject_position": 2, "title": "Sauna Lord"}
        )
        self.assertEqual(written.status_code, 200, written.text)
        stats = self.stats()
        self.assertEqual(
            (stats["period"], stats["from_day"], stats["to_day"]), ("week", 1, 4)
        )
        self.assertEqual(stats["reward_stars"], 0)
        self.assertEqual([s["key"] for s in stats["stats"]], list(player_stats.STATS))
        # Two challengers each (3 ★ each), and Alex's title.
        self.assertEqual(
            self.stat(stats, "stars-earned"), [(0, 9, 1), (1, 6, 2), (2, 6, 2)]
        )
        self.assertEqual(self.stat(stats, "busiest"), [(0, 3, 1), (1, 2, 2), (2, 2, 2)])
        # Nobody boosted yet, but chance: none of theirs.
        self.assertEqual(
            self.stat(stats, "most-boosts"), [(0, 0, 1), (1, 0, 1), (2, 0, 1)]
        )
        # Day 2's challengers, fought today: their own 3 ★ and the 3 boost
        # stars chance spread for each player. Day 3's aren't fought yet.
        self.assertEqual(
            self.stat(stats, "best-artist"), [(0, 6, 1), (1, 6, 1), (2, 6, 1)]
        )
        for subject in PLAYERS:
            self.assertEqual(self.stats(subject=subject), stats)

    def test_boosts_and_fights_count_once_done(self) -> None:
        # Day 4: Alex boosts one of day 3's challengers with all 3 stars.
        targets = self.today()["boost"]["targets"]
        self.assertEqual(
            self.boost_own({targets[0]["challenger"]["id"]: 3}).status_code, 200
        )
        stats = self.stats()
        self.assertEqual(self.stat(stats, "most-boosts")[0], (0, 3, 1))
        self.assertEqual(
            self.stat(stats, "busiest")[0], (0, 3, 1), "two drawings, a boost"
        )

        self.next_day()
        stats = self.stats()
        # Day 3's challengers were fought today: day 2's and day 3's each
        # have their own 3 ★, and every player's 3 boost stars went to them.
        artists = self.stat(stats, "best-artist")
        self.assertEqual(sum(v for _, v, _ in artists), 2 * (3 * 3 + 3 * 3))

    def boost_own(self, stars: dict[str, int]):
        return self.client.put(
            f"/servers/{self.code}/today/boosts",
            json={
                "boosts": [{"challenger_id": c, "stars": n} for c, n in stars.items()]
            },
            headers=bearer(make_token(ADMIN)),
        )

    def test_a_hot_streak_is_the_most_wins_in_a_row(self) -> None:
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            seat = session.scalar(
                select(ServerSeat).where(
                    ServerSeat.server_id == server.id, ServerSeat.position == 0
                )
            )
            challenger = session.scalar(
                select(Character).where(
                    Character.server_id == server.id, Character.assignment_id.is_(None)
                )
            )
            results = [True, True, False, True, True, True, False]
            chance = [False, False, False, False, True, False, False]
            for day, (won, by_chance) in enumerate(
                zip(results, chance, strict=True), 10
            ):
                session.add(
                    Fight(
                        id=uuid.uuid4(),
                        owner_seat_id=seat.id,
                        day=day,
                        challenger_id=challenger.id,
                        by_chance=by_chance,
                        boosts=2,
                        fighter_stars=6,
                        challenger_stars=5,
                        fighters_win=won,
                    )
                )
            session.commit()
            stats = player_stats.values(session, server, 10, 16)
            self.assertEqual(
                stats["hot-streak"][seat.id], 2, "chance's win doesn't count"
            )
            self.assertEqual(stats["most-wins"][seat.id], 4)
            self.assertEqual(stats["giant-slayer"][seat.id], 4 * 5)
            self.assertEqual(stats["busiest"][seat.id], 6)
            self.assertEqual(
                player_stats.values(session, server, 13, 16)["hot-streak"][seat.id], 2
            )

    def test_last_week_once_it_is_over_and_its_first_places_get_stars(self) -> None:
        self.assertIsNone(self.stats("last-week"))
        written = self.post(
            "today/prompt", ADMIN, {"subject_position": 2, "title": "Sauna Lord"}
        )
        self.assertEqual(written.status_code, 200, written.text)
        self.go_to_day(8)
        last = self.stats("last-week")
        self.assertEqual(
            (last["from_day"], last["to_day"], last["reward_stars"]), (1, 7, 3)
        )
        self.assertEqual(self.stat(last, "stars-earned")[0][::2], (0, 1))

        gifts = self.get(f"/servers/{self.code}/gifts").json()
        stars_earned = [g for g in gifts if "Stars earned" in g["message"]]
        self.assertEqual(len(stars_earned), 1)
        self.assertEqual((stars_earned[0]["stars"], stars_earned[0]["pulls"]), (3, 0))
        self.assertIn("week up to day 7", stars_earned[0]["message"])
        # Only the first place got it.
        for subject in PLAYERS[1:]:
            theirs = self.get(f"/servers/{self.code}/gifts", subject).json()
            self.assertFalse([g for g in theirs if "Stars earned" in g["message"]])
        # Nobody boosted themselves: no first place.
        self.assertFalse([g for g in gifts if "Most boosts" in g["message"]])
        # Ties share it: everyone drew as many challengers.
        for subject in PLAYERS:
            theirs = self.get(f"/servers/{self.code}/gifts", subject).json()
            self.assertEqual(
                sum("Busiest" in g["message"] for g in theirs), int(subject == ADMIN)
            )

        # Accepted, they don't count as stars earned, and come only once.
        accepted = self.post(f"gifts/{stars_earned[0]['id']}/accept")
        self.assertEqual(accepted.status_code, 200, accepted.text)
        self.today()
        self.assertEqual(self.stats("last-week"), last)
        gifts_again = self.get(f"/servers/{self.code}/gifts").json()
        self.assertEqual(len(gifts_again), len(gifts) - 1)

    def test_all_time_from_day_one(self) -> None:
        self.go_to_day(9)
        stats = self.stats("all")
        self.assertEqual((stats["from_day"], stats["to_day"]), (1, 9))
        week = self.stats("week")
        self.assertEqual((week["from_day"], week["to_day"]), (8, 9))
        everything = dict(self.stat(stats, "busiest")[i][:2] for i in range(3))
        this_week = dict(self.stat(week, "busiest")[i][:2] for i in range(3))
        for position, value in this_week.items():
            self.assertGreaterEqual(everything[position], value)

    def test_an_unknown_period_is_refused(self) -> None:
        response = self.get(f"/servers/{self.code}/player-stats?period=year")
        self.assertEqual(response.status_code, 422)


class SpeedPlayerStatsTests(SpeedTestCase):
    def test_speed_mode_has_none(self) -> None:
        self.launch()
        response = self.get(f"/servers/{self.code}/player-stats")
        self.assertEqual(response.status_code, 404)
