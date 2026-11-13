import uuid
from datetime import UTC, datetime
from unittest.mock import patch

from sqlalchemy import delete, select

from app import rules
from app.models import Fight, Fighter, Server, ServerSeat
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_fights import PLAYERS, FightTestCase


class WinRateTests(FightTestCase):
    """Last week's fights give this week's extra stars, between players."""

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

    def to_day_eight(self) -> None:
        """Moves on to day 8, the next Monday, leaving last week without any
        fighters but the ones `add_fight` adds."""
        while self.today()["day"] < 8:
            self.next_day()
        with self.session_factory() as session:
            session.execute(delete(Fighter))
            session.commit()

    def add_fight(self, owner: int, day: int, challenger: str, fighters, win: bool):
        """A decided fight of last week's, owner and day unique."""
        with self.session_factory() as session:
            seat = session.scalar(
                select(ServerSeat.id)
                .join(Server, Server.id == ServerSeat.server_id)
                .where(Server.code == self.code, ServerSeat.position == owner)
            )
            fight = Fight(
                owner_seat_id=seat,
                day=day,
                challenger_id=uuid.UUID(challenger),
                boosts=0,
                fighter_stars=1,
                challenger_stars=3,
                fighters_win=win,
            )
            fight.fighters = [
                Fighter(position=i, character_id=uuid.UUID(c))
                for i, c in enumerate(fighters)
            ]
            session.add(fight)
            session.commit()

    def win_rates(self) -> dict:
        return self.get(f"/servers/{self.code}/win-rates").json()

    def rival(self, challenger: dict) -> dict:
        """One of Alex's characters of a player other than the challenger's."""
        collection = self.get(f"/servers/{self.code}/collection").json()
        return next(
            o["character"]
            for o in collection
            if o["character"]["subject_position"] != challenger["subject_position"]
        )

    def test_the_first_week_has_no_win_rates(self) -> None:
        rates = self.win_rates()
        self.assertEqual((rates["from_day"], rates["to_day"]), (-6, 0))
        self.assertEqual(rates["min_fights"], rules.WIN_RATE_MIN_FIGHTS)
        self.assertEqual(rates["win_rates"], [])

    def test_winning_most_meetings_gives_fighters_extra_stars(self) -> None:
        self.to_day_eight()
        challenger = self.today()["fight"]["challenger"]
        fighter = self.rival(challenger)
        # Three meetings last week, all won by the fighter's player, and one
        # with a fighter of the challenger's own player, which doesn't count.
        for owner in range(3):
            self.add_fight(owner, 1, challenger["id"], [fighter["id"]], win=True)
        self.add_fight(0, 2, challenger["id"], [challenger["id"]], win=True)

        rates = self.win_rates()
        self.assertEqual((rates["from_day"], rates["to_day"]), (1, 7))
        player, against = fighter["subject_position"], challenger["subject_position"]
        self.assertEqual(
            sorted(
                rates["win_rates"],
                key=lambda r: r["player_position"] != player,
            ),
            [
                {
                    "player_position": player,
                    "against_position": against,
                    "fights": 3,
                    "wins": 3,
                    "extra_stars": 2,
                },
                {
                    "player_position": against,
                    "against_position": player,
                    "fights": 3,
                    "wins": 0,
                    "extra_stars": 0,
                },
            ],
        )

        # Two extra stars turn a loss into a win: 3 + 2 against 3 + 3.
        challenger_stars = 3 + self.boost_stars(challenger["id"])
        before = self.get(f"/servers/{self.code}/gacha").json()["stars"]
        with patch.object(rules, "team_stars", lambda team: challenger_stars - 1):
            fight = self.pick([fighter["id"]]).json()["fight"]["yours"]
        self.assertEqual([f["extra_stars"] for f in fight["fighters"]], [2])
        outcome = fight["outcome"]
        self.assertEqual(
            (outcome["fighter_extra_stars"], outcome["challenger_extra_stars"]), (2, 0)
        )
        self.assertTrue(outcome["fighters_win"])
        # The stars earned are the challenger's own and boost stars.
        gacha = self.get(f"/servers/{self.code}/gacha").json()
        self.assertEqual(gacha["stars"], before + challenger_stars)
        self.assertEqual(self.today()["fight"]["yours"], fight, "as stored")

    def test_winning_most_meetings_gives_challengers_extra_stars(self) -> None:
        self.to_day_eight()
        challenger = self.today()["fight"]["challenger"]
        fighter = self.rival(challenger)
        # The challenger's player won two of three meetings: one extra star
        # against each fighter of that player.
        for owner, win in enumerate((False, False, True)):
            self.add_fight(owner, 3, challenger["id"], [fighter["id"]], win=win)

        challenger_stars = 3 + self.boost_stars(challenger["id"])
        with patch.object(rules, "team_stars", lambda team: challenger_stars + 1):
            fight = self.pick([fighter["id"]]).json()["fight"]["yours"]
        outcome = fight["outcome"]
        self.assertEqual(
            (outcome["fighter_extra_stars"], outcome["challenger_extra_stars"]), (0, 1)
        )
        self.assertEqual([f["extra_stars"] for f in fight["fighters"]], [0])
        self.assertFalse(outcome["fighters_win"], "a tie goes to the challenger")

    def test_too_few_meetings_give_no_extra_stars(self) -> None:
        self.to_day_eight()
        challenger = self.today()["fight"]["challenger"]
        fighter = self.rival(challenger)
        for owner in range(2):
            self.add_fight(owner, 1, challenger["id"], [fighter["id"]], win=True)
        self.assertEqual({r["extra_stars"] for r in self.win_rates()["win_rates"]}, {0})
        fight = self.pick([fighter["id"]]).json()["fight"]["yours"]
        self.assertEqual(fight["outcome"]["fighter_extra_stars"], 0)
