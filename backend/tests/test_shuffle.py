"""Who draws whose prompt, and who boosts and fights whose challenger: handed
round at random afresh every day, never your own prompt or one of yourself
to draw (#239)."""

import random
import unittest
from collections import Counter
from datetime import UTC, datetime

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app import days, fights, setup
from app.database import SCHEMA, Base
from app.models import ChallengerPrompt, Character, Player, Server, ServerSeat

NAMES = ["Alex", "Sam", "Robin", "Kim", "Jo", "Max", "Lou", "Ari", "Noa", "Eli"]


class ShuffleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            poolclass=StaticPool,
            execution_options={"schema_translate_map": {SCHEMA: None}},
        )
        Base.metadata.create_all(self.engine)
        self.session: Session = sessionmaker(bind=self.engine, expire_on_commit=False)()

    def tearDown(self) -> None:
        self.session.close()
        self.engine.dispose()

    servers = 0

    def server(self, players: int, shuffled_from_day: int | None = 1) -> Server:
        self.servers += 1
        n = self.servers
        accounts = [Player(auth0_id=f"auth0|{name}{n}", first_name=name) for name in NAMES[:players]]
        self.session.add_all(accounts)
        self.session.flush()
        server = Server(
            code=f"{n:06d}",
            admin_id=accounts[0].id,
            launched_at=datetime(2026, 11, 2, tzinfo=UTC),
            is_test=True,
            test_day=40,
            shuffled_from_day=shuffled_from_day,
            seats=[
                ServerSeat(position=i, name=a.first_name, player_id=a.id)
                for i, a in enumerate(accounts)
            ],
        )
        self.session.add(server)
        self.session.commit()
        return server

    def write(self, server: Server, day: int, subjects: dict[int, int]) -> None:
        """Prompts written on `day`, by author position: of subject position."""
        seats = days.active_seats(server)
        for author, subject in subjects.items():
            self.session.add(
                ChallengerPrompt(
                    author_seat_id=seats[author].id,
                    day=day,
                    subject_seat_id=seats[subject].id,
                    title="Title",
                    theme=days.challenger_theme(server, day).value,
                )
            )
        self.session.commit()

    def handout(self, server: Server, prompt_day: int) -> dict[str, tuple[str, str]]:
        """Who draws what on the day after `prompt_day`: by drawer, the
        prompt's author and subject."""
        out = {}
        for drawer in days.active_seats(server):
            prompt = days.prompt_to_draw(self.session, server, prompt_day + 1, drawer)
            assert prompt is not None
            out[drawer.name] = (prompt.author.name, prompt.subject.name)
        return out

    def test_nobody_draws_their_own_prompt_or_one_of_themselves(self) -> None:
        rng = random.Random(239)
        for players in range(5, 11):
            server = self.server(players)
            for day in range(1, 15):
                # Some write a prompt of anyone else; the others skip.
                self.write(
                    server,
                    day,
                    {
                        a: rng.choice([s for s in range(players) if s != a])
                        for a in range(players)
                        if rng.random() < 0.7
                    },
                )
                handout = self.handout(server, day)
                authors = [author for author, _ in handout.values()]
                self.assertEqual(sorted(authors), sorted(handout), "every prompt drawn once")
                for drawer, (author, subject) in handout.items():
                    self.assertNotEqual(drawer, author, (players, day))
                    self.assertNotEqual(drawer, subject, (players, day))

    def test_the_handout_is_fresh_every_day(self) -> None:
        server = self.server(6)
        handouts = [tuple(sorted(self.handout(server, day).items())) for day in range(1, 21)]
        self.assertGreaterEqual(len(set(handouts)), 18, "hardly any day repeats another")
        alexs = Counter(next(d for d, (a, _) in h if a == "Alex") for h in handouts)
        self.assertEqual(len(alexs), 5, "Alex's prompts go to every other player")
        self.assertEqual(
            self.handout(server, 3), self.handout(server, 3), "the same every time it's asked"
        )

    def test_a_prompt_of_yourself_only_when_theres_no_way_round_it(self) -> None:
        # Everyone writes a prompt of Sam, and Sam one of Alex: Sam has to
        # draw a prompt of himself, but only he does.
        server = self.server(5)
        self.write(server, 1, {0: 1, 1: 0, 2: 1, 3: 1, 4: 1})
        clashes = [d for d, (_, subject) in self.handout(server, 1).items() if d == subject]
        self.assertEqual(clashes, ["Sam"])

    def test_running_servers_keep_the_roster_order_until_their_switch_day(self) -> None:
        for shuffled_from_day in (5, None):
            server = self.server(6, shuffled_from_day)
            names = [s.name for s in days.active_seats(server)]
            roster = {d: (names[(i - 1) % 6], "") for i, d in enumerate(names)}
            for day in range(1, 5):
                drawn = {d: (a, "") for d, (a, _) in self.handout(server, day).items()}
                self.assertEqual(drawn, roster, "the previous player's, as before")
            later = [
                {d: (a, "") for d, (a, _) in self.handout(server, day).items()} != roster
                for day in range(5, 12)
            ]
            self.assertEqual(any(later), shuffled_from_day is not None)

    def test_games_launched_from_now_on_shuffle_from_day_1(self) -> None:
        server = self.server(5, None)
        setup.launch(self.session, server)
        self.assertEqual(server.shuffled_from_day, 1)

    def test_every_challenger_is_fought_once_and_boosted_evenly_in_a_fresh_circle(self) -> None:
        players = 7
        server = self.server(players)
        seats = days.active_seats(server)
        fought_by: list[dict[str, str]] = []
        for drawn_day in range(2, 12):
            self.session.add_all(
                Character(
                    server_id=server.id,
                    artist_seat_id=seat.id,
                    subject_seat_id=seats[(i + 1) % players].id,
                    title="Title",
                    rarity="adventurer",
                    prompt="Title",
                    day=drawn_day,
                )
                for i, seat in enumerate(seats)
            )
            self.session.commit()
            fights_ = {
                s.name: fights.fight_challenger(self.session, server, drawn_day + 2, s)
                for s in seats
            }
            fought_by.append({s: c.artist.name for s, c in fights_.items() if c})
            self.assertEqual(len({c.id for c in fights_.values()}), players, "one fight each")
            boosts: Counter[str] = Counter()
            for seat in seats:
                targets = fights.boost_targets(self.session, server, drawn_day + 1, seat)
                fought = fights_[seat.name]
                for challenger in targets:
                    self.assertNotEqual(challenger.artist_seat_id, seat.id, "not your own")
                    self.assertNotEqual(challenger.id, fought.id, "not the one you fight")
                boosts.update(c.artist.name for c in targets)
            self.assertEqual(len(set(boosts.values())), 1, "boosted by as many players each")
            for fighter, artist in fought_by[-1].items():
                self.assertNotEqual(fighter, artist)
        # Not one shift of the roster for everyone, as before: within a day,
        # players fight challengers of players different seats on.
        for day in fought_by:
            offsets = {(NAMES.index(a) - NAMES.index(f)) % players for f, a in day.items()}
            self.assertGreater(len(offsets), 1)
        alexs = {day["Alex"] for day in fought_by}
        self.assertGreater(len(alexs), 3, "Alex fights different players' challengers")


if __name__ == "__main__":
    unittest.main()
