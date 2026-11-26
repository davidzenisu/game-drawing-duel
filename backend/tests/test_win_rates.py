import itertools
import unittest
import uuid
from datetime import UTC, datetime, timedelta
from unittest.mock import patch

from sqlalchemy import delete, select

from app import rules, win_rates
from app.models import ArenaVote, Character, Fight, Fighter, Server, ServerSeat
from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_fights import PLAYERS, FightTestCase

# The Arena whose votes give the win rates of days 15 to 21: the one of the
# challengers of days 1 to 7, voted on during days 8 to 14.
ARENA = 7


class MeetingTests(unittest.TestCase):
    """How Arena votes count as meetings between players."""

    def test_a_vote_is_a_meeting_its_winners_player_won(self) -> None:
        self.assertEqual(
            win_rates.meetings([("v", "sam", "alex"), ("w", "alex", "sam")], None),
            {("sam", "alex"): (1, 2), ("alex", "sam"): (1, 2)},
        )

    def test_portraits_of_the_same_player_count_for_nothing(self) -> None:
        self.assertEqual(win_rates.meetings([("v", "sam", "sam")], None), {})

    def test_each_voters_first_votes_on_a_pair_of_players_count(self) -> None:
        votes = [("v", "sam", "alex")] * 2 + [
            ("v", "alex", "sam"),
            ("w", "alex", "sam"),
        ]
        self.assertEqual(
            win_rates.meetings(votes, 2),
            {("sam", "alex"): (2, 3), ("alex", "sam"): (1, 3)},
        )


class WinRateTests(FightTestCase):
    """Last week's Arena votes give this week's extra stars, between the
    players the challengers portray."""

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

    def to_day(self, day: int) -> None:
        # Chance picks fighters for everyone every day: a seat without a fight
        # would get one picked once the fighters are gone.
        with self.without_rest():
            while self.today()["day"] < day:
                self.next_day()
        # No one rests from the fights chance picked: the fighters are free.
        with self.session_factory() as session:
            session.execute(delete(Fighter))
            session.commit()

    def seats(self) -> list[uuid.UUID]:
        with self.session_factory() as session:
            return list(
                session.scalars(
                    select(ServerSeat.id)
                    .join(Server, Server.id == ServerSeat.server_id)
                    .where(Server.code == self.code)
                    .order_by(ServerSeat.position)
                )
            )

    def add_votes(
        self,
        player: int,
        against: int,
        results: list[bool | None],
        *,
        voters: list[int] | None = None,
        week: int = ARENA,
    ) -> None:
        """Arena votes on matchups of characters portraying the players at
        roster positions `player` and `against`, in order: a win for
        `player`'s (True), for `against`'s (False) or a draw (None), each on
        another pair, by the voters (positions) taking turns."""
        seats = self.seats()
        voters = voters or list(range(len(seats)))
        with self.session_factory() as session:

            def portraits(position: int) -> list[uuid.UUID]:
                return list(
                    session.scalars(
                        select(Character.id)
                        .where(Character.subject_seat_id == seats[position])
                        .order_by(Character.id)
                    )
                )

            pairs = itertools.product(portraits(player), portraits(against))
            used = {
                (v.voter_seat_id, v.first_id, v.second_id)
                for v in session.scalars(select(ArenaVote))
            }
            start = datetime(2026, 10, 12, 9, tzinfo=UTC)
            for i, result in enumerate(results):
                voter = seats[voters[i % len(voters)]]
                ours, theirs = next(
                    (a, b)
                    for a, b in pairs
                    if (voter, *sorted((a, b), key=str)) not in used
                )
                first, second = sorted((ours, theirs), key=str)
                used.add((voter, first, second))
                session.add(
                    ArenaVote(
                        server_id=session.scalar(
                            select(Server.id).where(Server.code == self.code)
                        ),
                        voter_seat_id=voter,
                        week=week,
                        day=week + 3,
                        first_id=first,
                        second_id=second,
                        winner_id=None
                        if result is None
                        else ours
                        if result
                        else theirs,
                        voted_at=start + timedelta(minutes=len(used)),
                    )
                )
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

    def test_the_first_weeks_have_no_win_rates(self) -> None:
        rates = self.win_rates()
        self.assertEqual((rates["from_day"], rates["to_day"]), (-6, 0))
        self.assertEqual(rates["min_matchups"], rules.WIN_RATE_MIN_MATCHUPS)
        self.assertEqual(rates["matchups_per_voter"], rules.WIN_RATE_MATCHUPS_PER_VOTER)
        self.assertEqual(rates["win_rates"], [])

    def test_the_bands_come_with_the_win_rates(self) -> None:
        self.assertEqual(
            self.win_rates()["extra_stars"],
            [list(b) for b in rules.WIN_RATE_EXTRA_STARS],
        )

    def test_the_fights_dont_count(self) -> None:
        self.to_day(8)
        with self.session_factory() as session:
            fought = session.scalar(select(Fight.id).where(Fight.day < 8))
        self.assertIsNotNone(fought, "last week had fights")
        rates = self.win_rates()
        self.assertEqual((rates["from_day"], rates["to_day"]), (1, 7))
        self.assertEqual(rates["win_rates"], [], "no Arena was voted on last week")

    def test_winning_most_matchups_gives_fighters_extra_stars(self) -> None:
        self.to_day(15)
        challenger = self.today()["fight"]["challenger"]
        fighter = self.rival(challenger)
        player, against = fighter["subject_position"], challenger["subject_position"]
        # 6 of 10, exactly 60%; draws don't count.
        self.add_votes(player, against, [True] * 6 + [False] * 4 + [None] * 3)

        rates = self.win_rates()
        self.assertEqual((rates["from_day"], rates["to_day"]), (8, 14))
        self.assertEqual(
            sorted(rates["win_rates"], key=lambda r: r["player_position"] != player),
            [
                {
                    "player_position": player,
                    "against_position": against,
                    "matchups": 10,
                    "wins": 6,
                    "extra_stars": 1,
                },
                {
                    "player_position": against,
                    "against_position": player,
                    "matchups": 10,
                    "wins": 4,
                    "extra_stars": 0,
                },
            ],
        )

        # One extra star turns a tie, the challenger's, into a win.
        challenger_stars = 3 + self.boost_stars(challenger["id"])
        before = self.get(f"/servers/{self.code}/gacha").json()["stars"]
        with patch.object(rules, "team_stars", lambda team: challenger_stars):
            fight = self.pick([fighter["id"]]).json()["fight"]["yours"]
        self.assertEqual([f["extra_stars"] for f in fight["fighters"]], [1])
        outcome = fight["outcome"]
        self.assertEqual(
            (outcome["fighter_extra_stars"], outcome["challenger_extra_stars"]), (1, 0)
        )
        self.assertTrue(outcome["fighters_win"])
        # The stars earned are the challenger's own and boost stars.
        gacha = self.get(f"/servers/{self.code}/gacha").json()
        self.assertEqual(gacha["stars"], before + challenger_stars)
        self.assertEqual(self.today()["fight"]["yours"], fight, "as stored")

    def test_winning_most_matchups_gives_challengers_extra_stars(self) -> None:
        self.to_day(15)
        challenger = self.today()["fight"]["challenger"]
        fighter = self.rival(challenger)
        self.add_votes(
            challenger["subject_position"],
            fighter["subject_position"],
            [True] * 7 + [False] * 3,
        )

        challenger_stars = 3 + self.boost_stars(challenger["id"])
        with patch.object(rules, "team_stars", lambda team: challenger_stars + 1):
            fight = self.pick([fighter["id"]]).json()["fight"]["yours"]
        outcome = fight["outcome"]
        self.assertEqual(
            (outcome["fighter_extra_stars"], outcome["challenger_extra_stars"]), (0, 1)
        )
        self.assertEqual([f["extra_stars"] for f in fight["fighters"]], [0])
        self.assertFalse(outcome["fighters_win"], "a tie goes to the challenger")

    def test_less_than_60_percent_or_too_few_give_no_extra_stars(self) -> None:
        self.to_day(15)
        challenger = self.today()["fight"]["challenger"]
        fighter = self.rival(challenger)
        player, against = fighter["subject_position"], challenger["subject_position"]
        # 7 of 12, 58%: not enough.
        self.add_votes(player, against, [True] * 7 + [False] * 5)
        third = ({0, 1, 2} - {player, against}).pop()
        # 9 of 9: too few.
        self.add_votes(third, against, [True] * 9)
        self.assertEqual({r["extra_stars"] for r in self.win_rates()["win_rates"]}, {0})
        fight = self.pick([fighter["id"]]).json()["fight"]["yours"]
        outcome = fight["outcome"]
        self.assertEqual(
            (outcome["fighter_extra_stars"], outcome["challenger_extra_stars"]), (0, 0)
        )

    def test_only_each_voters_first_votes_on_a_pair_count(self) -> None:
        self.to_day(15)
        cap = rules.WIN_RATE_MATCHUPS_PER_VOTER
        # One voter: 5 wins and 5 losses, then 5 more wins that don't count.
        self.add_votes(0, 1, [True, False] * 5 + [True] * 5, voters=[2])
        (rate,) = [
            r for r in self.win_rates()["win_rates"] if r["player_position"] == 0
        ]
        self.assertEqual((rate["matchups"], rate["wins"]), (cap, 5))

    def test_only_the_arena_voted_on_last_week_counts(self) -> None:
        self.to_day(15)
        self.add_votes(0, 1, [True] * 10, week=ARENA - 7)
        self.add_votes(0, 1, [True] * 10, week=ARENA + 7)
        self.assertEqual(self.win_rates()["win_rates"], [])
