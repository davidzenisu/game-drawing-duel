from sqlalchemy import select

from app.models import Fight
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_launch import LaunchTestCase
from tests.test_setup import ADMIN, FRIEND_SUBJECTS, FRIENDS

SAM, ROBIN = FRIEND_SUBJECTS[:2]
PLAYERS = (ADMIN, SAM, ROBIN)


class FightTestCase(LaunchTestCase):
    def setUp(self) -> None:
        super().setUp()
        # A test session with Alex (seat 0), Sam (1) and Robin (2).
        self.code = self.create(is_test=True).json()["code"]
        for position, subject in enumerate((SAM, ROBIN), 1):
            self.sign_up(subject, FRIENDS[position - 1])
            self.claim(self.code, position, subject)
        self.start(self.code)
        for subject in PLAYERS:
            self.draw_all(self.code, subject)
            self.finish(self.code, subject)
        # Day 2: everyone draws a challenger from a premade prompt.
        self.next_day()
        for subject in PLAYERS:
            self.client.put(
                f"/servers/{self.code}/today/challenger",
                json={"sketch": SKETCH},
                headers=bearer(make_token(subject)),
            )
        self.next_day()

    def next_day(self):
        return self.post("days/next")

    def today(self, subject: str = ADMIN):
        return self.get(f"/servers/{self.code}/today", subject).json()

    def post(self, path: str, subject: str = ADMIN, json=None):
        return self.client.post(
            f"/servers/{self.code}/{path}",
            json=json,
            headers=bearer(make_token(subject)),
        )

    def pick(self, ids: list[str], subject: str = ADMIN):
        return self.client.put(
            f"/servers/{self.code}/today/fighters",
            json={"character_ids": ids},
            headers=bearer(make_token(subject)),
        )

    def owned(self, subject: str = ADMIN) -> list[str]:
        collection = self.get(f"/servers/{self.code}/collection", subject).json()
        return [o["character"]["id"] for o in collection]



class FightTests(FightTestCase):
    def test_day_three_brings_a_challenger_to_fight(self) -> None:
        fight = self.today()["fight"]
        self.assertEqual(fight["challenger"]["day"], 2)
        self.assertNotEqual(fight["challenger"]["artist_position"], 0, "not your own")
        self.assertIsNone(fight["yours"])

        response = self.pick(self.owned()[:2])
        self.assertEqual(response.status_code, 200, response.text)
        yours = response.json()["fight"]["yours"]
        self.assertEqual(len(yours["fighters"]), 2)
        self.assertFalse(yours["by_chance"])
        self.assertIsNone(yours["outcome"])
        self.assertEqual(self.pick(self.owned()[:1]).status_code, 409, "once a day")

    def test_fighters_must_be_yours_and_distinct(self) -> None:
        mine = self.owned()
        sams = self.owned(SAM)
        self.assertEqual(self.pick([sams[0]]).status_code, 409)
        self.assertEqual(self.pick([mine[0], mine[0]]).status_code, 422)
        self.assertEqual(self.pick([]).status_code, 422)
        self.assertEqual(self.pick(mine * 2).status_code, 422, "four at most")

    def test_yesterdays_fights_are_voted_on_and_decided_the_day_after(self) -> None:
        alex_fight = self.pick(self.owned()[:2]).json()["fight"]["yours"]
        challenger_artist = alex_fight["challenger"]["artist_position"]
        self.next_day()

        # Day 4: everyone but Alex and the challenger's artist votes. Sam and
        # Robin picked no fighters, so chance did.
        voter = PLAYERS[3 - challenger_artist]
        to_vote = self.today(voter)["to_vote"]
        ids = {f["id"]: f for f in to_vote}
        self.assertIn(alex_fight["id"], ids)
        with self.session_factory() as session:
            chance = session.scalars(
                select(Fight.by_chance).where(Fight.day == 3)
            ).all()
        self.assertEqual(sorted(chance), [False, True, True])
        self.assertTrue(all(f["outcome"] is None for f in to_vote), "votes stay secret")
        self.assertNotIn(alex_fight["id"], {f["id"] for f in self.today()["to_vote"]})

        response = self.post(
            f"today/votes/{alex_fight['id']}", voter, json={"fighters_win": True}
        )
        self.assertEqual(response.status_code, 200, response.text)
        voted = {f["id"]: f for f in response.json()["to_vote"]}
        self.assertTrue(voted[alex_fight["id"]]["your_vote"])
        again = self.post(
            f"today/votes/{alex_fight['id']}", voter, json={"fighters_win": False}
        )
        self.assertEqual(again.status_code, 409)
        own = self.post(f"today/votes/{alex_fight['id']}", json={"fighters_win": True})
        self.assertEqual(own.status_code, 403)

        # Day 5: the only eligible voter said the fighters win.
        self.next_day()
        results = {f["id"]: f for f in self.today()["results"]}
        self.assertEqual(
            results[alex_fight["id"]]["outcome"],
            {"fighter_votes": 1, "challenger_votes": 0, "fighters_win": True},
        )
        artist_results = self.today(PLAYERS[challenger_artist])["results"]
        self.assertIn(alex_fight["id"], {f["id"] for f in artist_results})
        self.assertEqual(self.today(voter)["to_vote"], [], "no fights on day 4")

    def test_missing_votes_are_decided_by_chance_and_stay_decided(self) -> None:
        alex_fight = self.pick(self.owned()[:1]).json()["fight"]["yours"]
        self.next_day()
        self.next_day()
        first = {f["id"]: f for f in self.today()["results"]}[alex_fight["id"]]
        self.assertEqual(
            first["outcome"]["fighter_votes"] + first["outcome"]["challenger_votes"], 1
        )
        again = {f["id"]: f for f in self.today()["results"]}[alex_fight["id"]]
        self.assertEqual(again["outcome"], first["outcome"])

    def test_no_fight_before_day_three(self) -> None:
        code = self.create(is_test=True).json()["code"]
        self.start(code)
        self.draw_all(code, ADMIN)
        self.finish(code)
        today = self.get(f"/servers/{code}/today").json()
        self.assertIsNone(today["fight"])
        response = self.client.put(
            f"/servers/{code}/today/fighters",
            json={"character_ids": self.owned()[:1]},
            headers=bearer(make_token(ADMIN)),
        )
        self.assertEqual(response.status_code, 409)
