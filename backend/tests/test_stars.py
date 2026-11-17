import uuid
from unittest.mock import patch

from sqlalchemy import select

from app import rules
from app.models import Player, Server, ServerSeat, StarGrant
from tests.test_fights import PLAYERS, SAM, FightTestCase
from tests.test_setup import ADMIN


class StarTests(FightTestCase):
    """Day 3 of a test session: everyone drew a challenger yesterday."""

    def stars(self, subject: str) -> int:
        return self.get(f"/servers/{self.code}/gacha", subject).json()["stars"]

    def write_prompt(self, subject: str):
        return self.post(
            "today/prompt", subject, {"subject_position": 0, "title": "Sauna Lord"}
        )

    def test_drawing_a_challenger_earns_three_stars(self) -> None:
        self.assertEqual(self.stars(SAM), 3, "yesterday's drawing")

    def test_writing_a_title_earns_three_stars_once_a_day(self) -> None:
        response = self.write_prompt(SAM)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.stars(SAM), 6)
        self.assertEqual(self.write_prompt(SAM).status_code, 409)
        self.assertEqual(self.stars(SAM), 6, "once")
        self.next_day()
        self.write_prompt(SAM)
        self.assertEqual(self.stars(SAM), 9, "and again the next day")


class ChallengerStarTests(FightTestCase):
    """The artist of a challenger that won its fight collects its stars."""

    def challengers(self, subject: str) -> list[dict]:
        return self.get(f"/servers/{self.code}/challengers", subject).json()

    def collect(self, challenger_id: str, subject: str):
        return self.post(f"challengers/{challenger_id}/stars", subject)

    def stars(self, subject: str) -> int:
        return self.get(f"/servers/{self.code}/gacha", subject).json()["stars"]

    def test_the_artist_collects_a_winning_challengers_stars_the_next_day(self) -> None:
        # Day 4: Alex loses against someone's challenger.
        self.next_day()
        challenger = self.today()["fight"]["challenger"]
        artist = PLAYERS[challenger["artist_position"]]
        with patch.object(rules, "team_stars", lambda team: 0):
            fight = self.pick(self.owned()[:1]).json()["fight"]["yours"]
        self.assertFalse(fight["outcome"]["fighters_win"])
        won = fight["outcome"]["challenger_stars"]

        def entry(subject: str) -> dict:
            return next(
                c for c in self.challengers(subject) if c["character"]["id"] == challenger["id"]
            )

        self.assertEqual(entry(artist)["stars_to_collect"], 0, "not before the day is over")
        # Day 5: the artist collects them, once.
        self.next_day()
        self.assertEqual(entry(artist)["stars_to_collect"], won)
        self.assertNotIn(
            challenger["id"],
            [c["character"]["id"] for c in self.challengers(ADMIN)],
            "only for its artist",
        )
        before = self.stars(artist)
        response = self.collect(challenger["id"], artist)
        self.assertEqual(response.status_code, 200, response.text)
        collected = next(c for c in response.json() if c["character"]["id"] == challenger["id"])
        self.assertEqual((collected["stars_to_collect"], collected["stars_collected"]), (0, won))
        self.assertEqual(self.stars(artist), before + won)
        self.collect(challenger["id"], artist)
        self.assertEqual(self.stars(artist), before + won, "once")
        self.assertEqual(self.collect(challenger["id"], ADMIN).status_code, 404)

    def test_a_beaten_challenger_has_no_stars_to_collect(self) -> None:
        self.next_day()
        challenger = self.today()["fight"]["challenger"]
        artist = PLAYERS[challenger["artist_position"]]
        with patch.object(rules, "team_stars", lambda team: 99):
            self.pick(self.owned()[:1])
        self.next_day()
        entry = next(
            c for c in self.challengers(artist) if c["character"]["id"] == challenger["id"]
        )
        self.assertEqual((entry["stars_to_collect"], entry["stars_collected"]), (0, 0))


class BuyPullTests(FightTestCase):
    """Day 3: everyone has their launch bonus and day 2's pull, and 3 stars."""

    def gacha(self, subject: str = ADMIN) -> dict:
        return self.get(f"/servers/{self.code}/gacha", subject).json()

    def buy(self, subject: str = ADMIN):
        return self.post("stars/pull", subject)

    def give_stars(self, stars: int, subject: str = ADMIN) -> None:
        with self.session_factory() as session:
            seat = session.scalars(
                select(ServerSeat)
                .join(Server)
                .join(Player, Player.id == ServerSeat.player_id)
                .where(Server.code == self.code, Player.auth0_id == subject)
            ).one()
            session.add(StarGrant(seat_id=seat.id, reason=f"test:{uuid.uuid4()}", stars=stars))
            session.commit()

    def test_ten_stars_buy_a_pull_with_pulls_left(self) -> None:
        tickets = self.gacha()["tickets"]
        self.assertGreater(tickets, 0)
        self.give_stars(20)
        bought = self.buy()
        self.assertEqual(bought.status_code, 200, bought.text)
        self.assertEqual((bought.json()["tickets"], bought.json()["stars"]), (tickets + 1, 13))
        self.assertEqual(self.buy().json()["stars"], 3, "and again")
        short = self.buy()
        self.assertEqual(short.status_code, 409)
        self.assertEqual(short.json()["detail"], "1 pull costs 10 stars")
        self.assertEqual(self.gacha()["stars"], 3)
        self.assertEqual(self.gacha()["tickets"], tickets + 2)

    def test_several_pulls_at_once(self) -> None:
        tickets = self.gacha()["tickets"]
        self.give_stars(27)
        short = self.post("stars/pull", ADMIN, {"count": 4})
        self.assertEqual(short.status_code, 409)
        self.assertEqual(short.json()["detail"], "4 pulls cost 40 stars")
        bought = self.post("stars/pull", ADMIN, {"count": 3})
        self.assertEqual(bought.status_code, 200, bought.text)
        self.assertEqual((bought.json()["tickets"], bought.json()["stars"]), (tickets + 3, 0))
        self.give_stars(10)
        self.buy()
        with self.session_factory() as session:
            reasons = session.scalars(
                select(StarGrant.reason).where(StarGrant.reason.like("pull:%"))
            ).all()
        self.assertEqual(sorted(reasons), ["pull:1", "pull:2", "pull:3", "pull:4"], "numbered")

    def test_a_pull_tops_up_the_pulls_it_is_short_of_with_stars(self) -> None:
        while self.gacha()["tickets"] > 3:
            self.post("pulls", ADMIN, {"count": min(self.gacha()["tickets"] - 3, 10)})
        tickets, total = self.gacha()["tickets"], self.gacha()["total_pulls"]
        self.give_stars(10 * (10 - tickets) - 3 - 1)
        short = self.post("pulls", ADMIN, {"count": 10, "top_up": True})
        self.assertEqual(short.status_code, 409, "a star short")
        self.assertEqual(self.gacha()["tickets"], tickets, "nothing bought")
        self.assertEqual(
            self.post("pulls", ADMIN, {"count": 10}).status_code, 409, "only when asked"
        )
        self.give_stars(1)
        response = self.post("pulls", ADMIN, {"count": 10, "top_up": True})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(len(response.json()["outcomes"]), 10)
        gacha = response.json()["gacha"]
        self.assertEqual((gacha["tickets"], gacha["stars"]), (0, 0))
        self.assertEqual(gacha["total_pulls"], total + 10, "counts towards the pity")

    def test_a_pull_with_enough_pulls_spends_no_stars(self) -> None:
        response = self.post("pulls", ADMIN, {"count": 1, "top_up": True})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["gacha"]["stars"], 3)
