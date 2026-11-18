import uuid

from sqlalchemy import select

from app import player_stats
from app.models import Character, Fight, Server, ServerSeat, Trophy
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_fights import ADMIN, PLAYERS
from tests.test_finale import FinaleTestCase
from tests.test_speed import SpeedTestCase


class PlayerStatsTests(FinaleTestCase):
    """The player stats of the week ranking and their trophies, see
    `app/player_stats.py`. Day 1 is a Monday; on day 4, everyone drew a
    challenger on days 2 and 3, and day 2's are fought. Nobody wrote a
    title yet."""

    def stats(self, period: str | None = None, subject: str = ADMIN):
        query = "" if period is None else f"?period={period}"
        response = self.get(f"/servers/{self.code}/player-stats{query}", subject)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    @staticmethod
    def stat(stats: dict, key: str) -> list[tuple[int, int | None, int | None]]:
        """A stat's ranking: (position, value, place) per player."""
        entry = next(s for s in stats["stats"] if s["key"] == key)
        return [
            (p["player_position"], p["value"], p["place"]) for p in entry["players"]
        ]

    @staticmethod
    def trophies(stats: dict, key: str) -> dict[int, int]:
        entry = next(s for s in stats["stats"] if s["key"] == key)
        return {p["player_position"]: p["trophies"] for p in entry["players"]}

    def gifts(self, subject: str = ADMIN) -> list[dict]:
        return self.get(f"/servers/{self.code}/gifts", subject).json()

    def do_all(self, subject: str = ADMIN) -> None:
        """Every daily step `subject` can do today."""
        headers = bearer(make_token(subject))
        position = PLAYERS.index(subject)
        today = self.today(subject)
        if today["prompt"] is not None:
            written = self.post(
                "today/prompt",
                subject,
                {"subject_position": (position + 1) % 3, "title": "Busy Bee"},
            )
            self.assertEqual(written.status_code, 200, written.text)
        if today["to_draw"] is not None:
            drawn = self.client.put(
                f"/servers/{self.code}/today/challenger",
                json={"sketch": SKETCH},
                headers=headers,
            )
            self.assertEqual(drawn.status_code, 200, drawn.text)
        if today["boost"] and today["boost"]["targets"]:
            target = today["boost"]["targets"][0]["challenger"]["id"]
            boosted = self.client.put(
                f"/servers/{self.code}/today/boosts",
                json={"boosts": [{"challenger_id": target, "stars": 3}]},
                headers=headers,
            )
            self.assertEqual(boosted.status_code, 200, boosted.text)
        if today["fight"] and today["fight"]["yours"] is None:
            resting = set(today["fight"]["resting"])
            free = [c for c in self.owned(subject) if c not in resting]
            if free:
                self.assertEqual(self.pick(free[:1], subject).status_code, 200)

    def test_every_category_ranks_every_player_and_boosts_are_secret(self) -> None:
        stats = self.stats()
        self.assertEqual(
            (stats["period"], stats["from_day"], stats["to_day"]), ("week", 1, 4)
        )
        self.assertEqual(stats["trophy_stars"], 3)
        self.assertEqual([s["key"] for s in stats["stats"]], list(player_stats.STATS))
        self.assertEqual(
            self.stat(stats, "most-wins"), [(0, 0, 1), (1, 0, 1), (2, 0, 1)]
        )
        boosted = next(s for s in stats["stats"] if s["key"] == "most-boosted")
        self.assertTrue(boosted["secret"], "it would tell how strong a drawing is")
        self.assertEqual(
            self.stat(stats, "most-boosted"),
            [(0, None, None), (1, None, None), (2, None, None)],
        )
        # Nobody wrote a title yet; today isn't over, so it doesn't break it.
        self.assertEqual(
            self.stat(stats, "busy-streak"), [(0, 0, 1), (1, 0, 1), (2, 0, 1)]
        )
        self.do_all()
        stats = self.stats()
        self.assertEqual(self.stat(stats, "busy-streak")[0], (0, 1, 1))
        self.assertEqual(self.stat(stats, "busy-streak")[1][1:], (0, 2))
        for subject in PLAYERS:
            self.assertEqual(self.stats(subject=subject), stats)

    def test_a_busy_streak_runs_across_weeks_and_wins_a_trophy(self) -> None:
        with self.without_rest():
            for _ in range(4, 8):
                self.do_all()
                self.next_day()
            # Day 8, a Monday: the week of days 1 to 7 is over.
            last = self.stats("last-week")
            self.assertEqual((last["from_day"], last["to_day"]), (1, 7))
            self.assertEqual(self.stat(last, "busy-streak")[0], (0, 4, 1))
            self.assertEqual(self.trophies(last, "busy-streak"), {0: 1, 1: 0, 2: 0})
            # Last week's boosts aren't secret anymore: the challengers it
            # counts were all fought by Sunday.
            boosted = next(s for s in last["stats"] if s["key"] == "most-boosted")
            self.assertFalse(boosted["secret"])
            self.assertTrue(
                all(v is not None for _, v, _ in self.stat(last, "most-boosted"))
            )

            mine = [
                g
                for g in self.gifts()
                if g["message"].startswith("Trophy: Addict")
            ]
            self.assertEqual(len(mine), 1)
            self.assertEqual((mine[0]["stars"], mine[0]["pulls"]), (3, 0))
            self.assertEqual(mine[0]["message"], "Trophy: Addict in week 1!")
            for subject in PLAYERS[1:]:
                self.assertFalse(
                    [g for g in self.gifts(subject) if "Addict" in g["message"]]
                )

            self.do_all()
            self.next_day()
            self.do_all()
            week = self.stats()
            self.assertEqual((week["from_day"], week["to_day"]), (8, 9))
            self.assertEqual(
                self.stat(week, "busy-streak")[0], (0, 6, 1), "days 4 to 9"
            )
        # Awarded only once.
        self.today()
        trophy_gifts = [
            g for g in self.gifts() if g["message"].startswith("Trophy: Addict")
        ]
        self.assertEqual(len(trophy_gifts), 1)
        with self.session_factory() as session:
            won = session.scalars(select(Trophy).where(Trophy.stat == "busy-streak"))
            self.assertEqual(len(won.all()), 1)

    def test_ties_share_the_trophy_and_nothing_for_zero(self) -> None:
        with self.without_rest():
            self.go_to_day(8)
        last = self.stats("last-week")
        # Every player's challengers got as many boost stars: a tie.
        boosted = self.stat(last, "most-boosted")
        self.assertEqual({place for _, _, place in boosted}, {1}, boosted)
        for subject in PLAYERS:
            gifts = self.gifts(subject)
            self.assertEqual(
                sum(g["message"].startswith("Trophy: Grand Artist") for g in gifts), 1
            )
            # Nobody picked fighters themselves: no trophy.
            self.assertFalse([g for g in gifts if "Giant Slayer" in g["message"]])
        self.assertEqual(
            self.trophies(self.stats(), "most-boosted"), {0: 1, 1: 1, 2: 1}
        )

    def test_most_fights_won_counts_only_the_ones_you_picked(self) -> None:
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
            results = [True, True, False, True]
            chance = [False, False, False, True]
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
            wins = player_stats.values(session, server, 10, 16)["most-wins"]
            self.assertEqual(wins[seat.id], 2)
            wins = player_stats.values(session, server, 11, 16)["most-wins"]
            self.assertEqual(wins[seat.id], 1)

    def test_who_the_weeks_challengers_portray_without_their_stars(self) -> None:
        stats = self.stats()
        portrayed = {p["player_position"]: p["challengers"] for p in stats["portrayed"]}
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            self.assertEqual(
                sorted(portrayed), sorted(s.position for s in server.seats)
            )
        # Days 2 and 3's challengers, fought on days 4 and 5.
        self.assertEqual(sum(portrayed.values()), 6)
        self.assertNotIn("stars", stats["portrayed"][0])

    def test_no_last_week_before_the_first_is_over(self) -> None:
        self.assertIsNone(self.stats("last-week"))

    def test_an_unknown_period_is_refused(self) -> None:
        response = self.get(f"/servers/{self.code}/player-stats?period=all")
        self.assertEqual(response.status_code, 422)


class SpeedPlayerStatsTests(SpeedTestCase):
    def test_speed_mode_has_none(self) -> None:
        self.launch()
        response = self.get(f"/servers/{self.code}/player-stats")
        self.assertEqual(response.status_code, 404)
