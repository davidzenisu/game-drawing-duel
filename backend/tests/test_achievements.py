from sqlalchemy import select

from app import rules
from app.models import Character, Fight, Pull, PullGrant, Server, ServerSeat
from tests.test_fights import PLAYERS, FightTestCase
from tests.test_setup import ADMIN


class AchievementTests(FightTestCase):
    """See `app/achievements.py`."""

    def achievements(self, subject: str = ADMIN) -> dict[str, dict]:
        response = self.get(f"/servers/{self.code}/achievements", subject)
        self.assertEqual(response.status_code, 200, response.text)
        return {a["key"]: a for a in response.json()}

    def collect(self, key: str, subject: str = ADMIN):
        return self.post(f"achievements/{key}/collect", subject)

    def stars(self, subject: str = ADMIN) -> int:
        return self.get(f"/servers/{self.code}/gacha", subject).json()["stars"]

    def seat(self, session, position: int) -> ServerSeat:
        return session.scalar(
            select(ServerSeat)
            .join(Server, Server.id == ServerSeat.server_id)
            .where(Server.code == self.code, ServerSeat.position == position)
        )

    def starters(self) -> list[Character]:
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            return list(
                session.scalars(
                    select(Character).where(
                        Character.server_id == server.id,
                        Character.assignment_id.is_not(None),
                    )
                )
            )

    def own(self, characters: list[Character], position: int = 0) -> None:
        """Alex pulled these, with launch pulls."""
        with self.session_factory() as session:
            seat = self.seat(session, position)
            used = session.scalars(select(Pull).where(Pull.seat_id == seat.id)).all()
            grants = [
                g
                for g in session.scalars(
                    select(PullGrant).where(PullGrant.seat_id == seat.id)
                )
                if g.id not in {p.grant_id for p in used}
            ]
            pairs = zip(grants, characters, strict=False)
            for n, (grant, character) in enumerate(pairs, len(used) + 1):
                session.add(
                    Pull(
                        seat_id=seat.id,
                        grant_id=grant.id,
                        character_id=character.id,
                        number=n,
                        rarity=character.rarity,
                    )
                )
            session.commit()

    def fought(
        self,
        results: list[bool],
        by_chance: bool = False,
        fighter_stars: int | None = None,
        challenger_extra_stars: int = 0,
        first_day: int = 4,
    ) -> None:
        """Alex's fights on days `first_day`, the day after, … with these
        outcomes, against a 3 star challenger: won by 2 stars unless
        `fighter_stars` says otherwise."""
        challenger = self.starters()[0]
        with self.session_factory() as session:
            seat = self.seat(session, 0)
            for day, won in enumerate(results, first_day):
                session.add(
                    Fight(
                        owner_seat_id=seat.id,
                        day=day,
                        challenger_id=challenger.id,
                        by_chance=by_chance,
                        boosts=0,
                        fighter_stars=fighter_stars or (5 if won else 1),
                        challenger_stars=3,
                        challenger_extra_stars=challenger_extra_stars,
                        fighters_win=won,
                    )
                )
            session.commit()

    def test_the_achievements_and_their_rewards(self) -> None:
        achievements = self.achievements()
        starters = self.starters()
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            positions = {s.id: s.position for s in server.seats}
            players = len(server.seats)
        artists = sorted({positions[c.artist_seat_id] for c in starters} - {0})
        subjects = sorted({positions[c.subject_seat_id] for c in starters})
        self.assertEqual(
            list(achievements),
            [f"artist:{p}" for p in artists]
            + [f"portrait:{p}" for p in subjects]
            + ["rarity:basic", "rarity:adventurer", "rarity:legend"]
            + [f"wins:{n}" for n in (1, 3, 5, 10, 25, 50)]
            + [f"streak:{n}" for n in range(3, 26)]
            + [f"close:{n}" for n in (1, 3, 5, 10, 25, 50)],
            "your own drawings are yours from the start",
        )
        reward = rules.ACHIEVEMENT_PLAYER_STARS[min(max(players, 5), 10)]
        artist = achievements[f"artist:{artists[0]}"]
        self.assertEqual(artist["kind"], "artist")
        self.assertEqual(artist["player_position"], artists[0])
        self.assertEqual(
            artist["goal"],
            sum(positions[c.artist_seat_id] == artists[0] for c in starters),
        )
        self.assertEqual((artist["progress"], artist["stars"]), (0, reward))
        self.assertEqual(achievements["rarity:legend"]["stars"], 20)
        self.assertEqual(achievements["rarity:legend"]["rarity"], "legend")
        self.assertEqual(achievements["wins:10"]["stars"], 5)
        self.assertEqual(achievements["streak:25"]["stars"], 5)
        self.assertEqual(achievements["close:50"]["stars"], 5)
        self.assertFalse(any(a["collected"] for a in achievements.values()))

    def test_owning_an_artists_starter_heroes_earns_their_stars_once(self) -> None:
        starters = self.starters()
        with self.session_factory() as session:
            sam = self.seat(session, 1).id
        drawn = [c for c in starters if c.artist_seat_id == sam]
        self.assertTrue(drawn)
        self.own(drawn[:-1])
        self.assertEqual(self.achievements()["artist:1"]["progress"], len(drawn) - 1)
        refused = self.collect("artist:1")
        self.assertEqual(refused.status_code, 409)
        self.assertEqual(refused.json()["detail"], "Not achieved yet")

        self.own(drawn)
        artist = self.achievements()["artist:1"]
        self.assertTrue(artist["done"])
        before = self.stars()
        collected = self.collect("artist:1")
        self.assertEqual(collected.status_code, 200, collected.text)
        self.assertTrue({a["key"]: a for a in collected.json()}["artist:1"]["collected"])
        self.assertEqual(self.stars(), before + artist["stars"])
        self.assertEqual(self.collect("artist:1").status_code, 200)
        self.assertEqual(self.stars(), before + artist["stars"], "only once")
        # Everyone has their own.
        self.assertFalse(self.achievements(PLAYERS[1]).get("artist:1"))

    def test_wins_and_streaks_count_the_fights_you_picked(self) -> None:
        self.fought([True, True, False, True, True, True])
        achievements = self.achievements()
        self.assertEqual(achievements["wins:3"]["progress"], 3)
        self.assertTrue(achievements["wins:3"]["done"])
        self.assertEqual(achievements["wins:10"]["progress"], 5)
        self.assertTrue(achievements["streak:3"]["done"])
        self.assertEqual(achievements["streak:5"]["progress"], 3, "a loss starts over")

        before = self.stars()
        for key in ("wins:1", "wins:3", "streak:3"):
            self.assertEqual(self.collect(key).status_code, 200)
        self.assertEqual(self.stars(), before + 3 * rules.ACHIEVEMENT_FIGHT_STARS)
        self.assertEqual(self.collect("streak:5").status_code, 409)
        self.assertEqual(self.collect("nope:1").status_code, 409)

    def test_wins_by_chance_dont_count(self) -> None:
        self.fought([True] * 3, by_chance=True)
        self.assertEqual(self.achievements()["wins:1"]["progress"], 0)

    def test_close_calls_are_wins_by_exactly_one_star(self) -> None:
        self.fought([True], fighter_stars=4)  # 4 against 3
        self.fought([True], fighter_stars=5, first_day=5)  # 5 against 3
        self.assertEqual(self.achievements()["close:1"]["progress"], 1)
        # 5 against 3 with 1 extra star, and a loss by one star.
        self.fought([True], fighter_stars=5, challenger_extra_stars=1, first_day=6)
        self.fought([False], fighter_stars=3, first_day=7)
        achievements = self.achievements()
        self.assertEqual(achievements["close:3"]["progress"], 2, "extra stars count")
        self.assertEqual(achievements["wins:3"]["progress"], 3)

        before = self.stars()
        self.assertEqual(self.collect("close:1").status_code, 200)
        self.assertEqual(self.stars(), before + rules.ACHIEVEMENT_FIGHT_STARS)
        self.assertEqual(self.collect("close:3").status_code, 409)

    def test_close_calls_by_chance_dont_count(self) -> None:
        self.fought([True], by_chance=True, fighter_stars=4)
        self.assertEqual(self.achievements()["close:1"]["progress"], 0)

    def test_speed_mode_lists_no_levels_out_of_reach(self) -> None:
        with self.session_factory() as session:
            server = session.scalar(select(Server).where(Server.code == self.code))
            server.mode = "speed"
            session.commit()
        self.fought([True] * 5)
        achievements = self.achievements()
        fights = [
            k for k in achievements if k.split(":")[0] in ("wins", "streak", "close")
        ]
        self.assertEqual(
            fights,
            ["wins:1", "wins:3", "streak:3"]
            + ["close:1", "close:3"],
        )
        self.assertEqual(self.collect("wins:5").status_code, 409)
