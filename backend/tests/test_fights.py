import uuid
from datetime import UTC, datetime

from sqlalchemy import select

from app import fights
from app.models import Boost, Fight, Fighter, Server, ServerSeat
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_launch import LaunchTestCase
from tests.test_setup import ADMIN, FRIEND_SUBJECTS, FRIENDS

STARS = {"basic": 1, "adventurer": 2, "hero": 3, "legend": 4}

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

    def stars(self, fight: dict) -> int:
        return sum(STARS[f["character"]["rarity"]] for f in fight["fighters"])

    def test_yesterdays_challengers_are_boosted_and_the_stars_decide(self) -> None:
        alex_fight = self.pick(self.owned()[:2]).json()["fight"]["yours"]
        self.next_day()

        # Day 4: everyone may boost one of yesterday's challengers, but not the
        # one they drew or the one they fought. Sam and Robin picked no
        # fighters, so chance did.
        with self.session_factory() as session:
            chance = session.scalars(
                select(Fight.by_chance).where(Fight.day == 3)
            ).all()
        self.assertEqual(sorted(chance), [False, True, True])
        targets = {}
        for position, subject in enumerate(PLAYERS):
            today = self.today(subject)
            self.assertEqual(today["results"], [], "nothing decided yet")
            for target in today["to_boost"]:
                self.assertNotEqual(target["challenger"]["artist_position"], position)
                for matchup in target["matchups"]:
                    self.assertEqual(
                        matchup["challenger"]["id"], target["challenger"]["id"]
                    )
                    self.assertNotEqual(matchup["owner_position"], position)
                    self.assertIsNone(matchup["outcome"], "decided tomorrow")
            targets[subject] = today["to_boost"]
            self.assertIsNone(today["boosted"])
        alex_targets = {t["challenger"]["id"] for t in targets[ADMIN]}
        self.assertNotIn(alex_fight["challenger"]["id"], alex_targets)

        booster = next(s for s in PLAYERS if targets[s])
        target = targets[booster][0]["challenger"]["id"]
        response = self.post("today/boosts", booster, json={"challenger_id": target})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["boosted"], target)
        again = self.post("today/boosts", booster, json={"challenger_id": target})
        self.assertEqual(again.status_code, 409)
        unknown = self.post(
            "today/boosts", booster, json={"challenger_id": str(uuid.uuid4())}
        )
        self.assertEqual(unknown.status_code, 404)
        own = self.post(
            "today/boosts",
            json={"challenger_id": alex_fight["challenger"]["id"]},
        )
        self.assertEqual(own.status_code, 404, "not the one you fought")

        # Day 5: one boost gives the challenger 3 + 1 stars.
        self.next_day()
        self.assertEqual(self.today(booster)["to_boost"], [], "no fights on day 4")
        with self.session_factory() as session:
            owners = session.scalars(
                select(ServerSeat.position)
                .join(Fight, Fight.owner_seat_id == ServerSeat.id)
                .where(Fight.challenger_id == uuid.UUID(target))
            ).all()
        for position in owners:
            [result] = [
                r
                for r in self.today(PLAYERS[position])["results"]
                if r["challenger"]["id"] == target
            ]
            stars = self.stars(result)
            self.assertEqual(
                result["outcome"],
                {
                    "fighter_stars": stars,
                    "boosts": 1,
                    "challenger_stars": 4,
                    "fighters_win": stars > 4,
                },
            )

    def test_boosts_stack_and_ties_go_to_the_challenger(self) -> None:
        alex_fight = self.pick(self.owned()[:1]).json()["fight"]["yours"]
        challenger = uuid.UUID(alex_fight["challenger"]["id"])
        self.next_day()
        with self.session_factory() as session:
            seats = session.scalars(
                select(ServerSeat)
                .join(Server, Server.id == ServerSeat.server_id)
                .where(Server.code == self.code, ServerSeat.player_id.is_not(None))
            ).all()
            session.add_all(
                Boost(booster_seat_id=s.id, challenger_id=challenger, day=4)
                for s in seats
            )
            session.commit()
        self.next_day()
        [result] = [r for r in self.today()["results"] if r["id"] == alex_fight["id"]]
        self.assertEqual(
            result["outcome"],
            {
                "fighter_stars": self.stars(result),
                "boosts": 3,
                "challenger_stars": 9,
                "fighters_win": False,
            },
        )
        again = [r for r in self.today()["results"] if r["id"] == alex_fight["id"]]
        self.assertEqual(again, [result], "stays decided")

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


class ChallengerListTests(FightTestCase):
    def challengers(self, subject: str = ADMIN) -> dict[str, dict]:
        listed = self.get(f"/servers/{self.code}/challengers", subject).json()
        return {c["character"]["id"]: c for c in listed}

    def test_challengers_you_drew_fought_or_boosted_with_their_record(self) -> None:
        drawn = {
            subject: self.client.get(
                f"/servers/{self.code}/challengers", headers=bearer(make_token(subject))
            ).json()[0]["character"]["id"]
            for subject in PLAYERS
        }
        alex_fight = self.pick(self.owned()[:2]).json()["fight"]["yours"]
        opponent = alex_fight["challenger"]["id"]
        self.assertEqual(set(self.challengers()), {drawn[ADMIN], opponent})
        self.assertEqual(self.challengers()[opponent]["fights"], 0, "not decided yet")
        self.next_day()

        # Day 4: a player encounters the challenger they boost.
        boosters = [
            (subject, target["challenger"]["id"])
            for subject in PLAYERS
            for target in self.today(subject)["to_boost"]
            if target["challenger"]["id"] not in self.challengers(subject)
        ]
        self.assertTrue(boosters)
        booster, target = boosters[0]
        response = self.post("today/boosts", booster, json={"challenger_id": target})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertIn(target, self.challengers(booster))
        self.next_day()

        # Day 5: the day 3 fights are decided.
        record = self.challengers()[opponent]
        with self.session_factory() as session:
            against = session.scalars(
                select(Fight).where(Fight.challenger_id == uuid.UUID(opponent))
            ).all()
            wins = sum(not fights.outcome(session, f).fighters_win for f in against)
        self.assertEqual((record["fights"], record["wins"]), (len(against), wins))
        self.assertGreaterEqual(record["fights"], 1)

    def test_pulls_never_return_challengers(self) -> None:
        challengers = set()
        for subject in PLAYERS:
            challengers |= set(self.challengers(subject))
        self.assertTrue(challengers)
        response = self.post("pulls", json={"count": 10})
        self.assertEqual(response.status_code, 200, response.text)
        pulled = {o["character"]["id"] for o in response.json()["outcomes"]}
        self.assertFalse(pulled & challengers)
        pool = {c["id"] for c in self.get(f"/servers/{self.code}/pool").json()}
        self.assertFalse(pool & challengers)


class WeeklyRestTests(FightTestCase):
    """Every character fights once a week, from Monday to Sunday (UTC)."""

    def setUp(self) -> None:
        super().setUp()
        # Day 1 is a Monday: days 1 to 7 are a week, day 8 starts the next.
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            server.launched_at = datetime(2026, 10, 5, 9, tzinfo=UTC)
            session.commit()

    def next_day(self):
        # Everyone draws a challenger, so there's one to fight tomorrow.
        for subject in PLAYERS:
            self.client.put(
                f"/servers/{self.code}/today/challenger",
                json={"sketch": SKETCH},
                headers=bearer(make_token(subject)),
            )
        return super().next_day()

    def fighters_of(self, subject: str, day: int) -> set[str]:
        with self.session_factory() as session:
            return {
                str(c)
                for c in session.scalars(
                    select(Fighter.character_id)
                    .join(Fight, Fight.id == Fighter.fight_id)
                    .join(ServerSeat, ServerSeat.id == Fight.owner_seat_id)
                    .join(Server, Server.id == ServerSeat.server_id)
                    .where(
                        Server.code == self.code,
                        ServerSeat.position == PLAYERS.index(subject),
                        Fight.day == day,
                    )
                )
            }

    def rarities(self, subject: str = ADMIN) -> dict[str, str]:
        collection = self.get(f"/servers/{self.code}/collection", subject).json()
        return {o["character"]["id"]: o["character"]["rarity"] for o in collection}

    def test_characters_rest_until_monday_after_a_fight(self) -> None:
        rarities = self.rarities()
        rare = [c for c, r in rarities.items() if r != "basic"][:2]
        basic = next(c for c, r in rarities.items() if r == "basic")
        self.assertEqual(len(rare), 2)
        self.assertEqual(self.today()["fight"]["resting"], [])
        self.assertEqual(self.pick([*rare, basic]).status_code, 200)
        self.next_day()

        # Day 4: the two rarer fighters rest for the rest of the week, the
        # basic one fights again.
        self.assertEqual(set(self.today()["fight"]["resting"]), set(rare))
        again = self.pick([rare[0], basic])
        self.assertEqual(again.status_code, 409)
        self.assertEqual(
            again.json()["detail"],
            "Every character fights once a week; they're back on Monday",
        )
        self.assertEqual(self.pick([basic]).status_code, 200)

        # Day 8 is the next Monday: everyone is back.
        for _ in range(4):
            self.next_day()
        self.assertEqual(self.today()["day"], 8)
        self.assertEqual(self.today()["fight"]["resting"], [])
        self.assertEqual(self.pick(rare).status_code, 200)

    def test_fighters_picked_by_chance_rest_too(self) -> None:
        # Sam picks nobody all week, so chance does, from the characters
        # that didn't fight yet that week, or basic ones.
        rarities = self.rarities(SAM)
        picked = set()
        for day in range(3, 8):
            # A day's missing fighters are picked once the next day starts.
            self.next_day()
            self.today(SAM)
            fighters = self.fighters_of(SAM, day)
            self.assertTrue(fighters, f"day {day}: a basic one is always left")
            rested = {c for c in picked & fighters if rarities[c] != "basic"}
            self.assertFalse(rested, f"day {day}")
            picked |= fighters


class StackedHurryTests(FightTestCase):
    def test_every_hurry_a_player_receives_counts(self) -> None:
        for sender in (ADMIN, SAM):
            response = self.post("today/hurry", sender, json={"target_position": 2})
            self.assertEqual(response.status_code, 200, response.text)
        hurries = self.today(ROBIN)["incoming_hurries"]
        self.assertEqual({h["by_position"] for h in hurries}, {0, 1})
        fractions = [h["at_fraction"] for h in hurries]
        self.assertEqual(fractions, sorted(fractions), "in the order they hit")
