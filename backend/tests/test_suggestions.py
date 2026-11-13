from tests.helpers import bearer, make_token
from tests.test_servers import ADMIN, ServerTestCase

SAM = "auth0|sam"
KIM = "auth0|kim"


class SuggestionTests(ServerTestCase):
    """A lobby with Alex (the admin) and Sam; Kim plays on another server."""

    def setUp(self) -> None:
        super().setUp()
        self.code = self.create().json()["code"]
        self.sign_up(SAM, "Sam")
        self.assertEqual(self.claim(self.code, 1, SAM).status_code, 200)
        self.sign_up(KIM, "Kim")
        other = self.create(["Lee", "Max", "Ana", "Tom"], subject=KIM)
        self.assertEqual(other.status_code, 201, other.text)
        self.other = other.json()["code"]

    def suggest(self, subject: str = ADMIN, code: str | None = None, **body):
        return self.client.post(
            f"/servers/{code or self.code}/suggestions",
            json={
                "kind": "idea",
                "title": "Dark mode",
                "description": "Easier on the eyes at night.",
                **body,
            },
            headers=bearer(make_token(subject)),
        )

    def board(self, subject: str = ADMIN, code: str | None = None):
        return self.client.get(
            f"/servers/{code or self.code}/suggestions",
            headers=bearer(make_token(subject)),
        )

    def vote(self, suggestion_id: str, subject: str, up: bool = True):
        method = self.client.put if up else self.client.delete
        return method(
            f"/servers/{self.code}/suggestions/{suggestion_id}/vote",
            headers=bearer(make_token(subject)),
        )

    def test_players_post_ideas_and_bugs_the_server_sees(self) -> None:
        posted = self.suggest(title="  Dark mode  ")
        self.assertEqual(posted.status_code, 201, posted.text)
        idea = posted.json()
        self.assertEqual(
            (idea["kind"], idea["title"], idea["author"], idea["votes"], idea["yours"]),
            ("idea", "Dark mode", "Alex", 0, True),
        )
        bug = self.suggest(SAM, kind="bug", title="Crash on undo").json()
        board = self.board(SAM).json()
        self.assertEqual({s["title"] for s in board}, {"Dark mode", "Crash on undo"})
        mine = next(s for s in board if s["id"] == bug["id"])
        self.assertEqual((mine["author"], mine["yours"]), ("Sam", True))
        self.assertEqual(self.board(SAM).json()[0]["description"], board[0]["description"])

    def test_only_the_servers_players_see_and_post(self) -> None:
        self.suggest()
        self.assertEqual(self.board(KIM).status_code, 403)
        self.assertEqual(self.suggest(KIM).status_code, 403)
        self.assertEqual(self.board(KIM, self.other).json(), [], "another server's board")
        self.suggest(KIM, self.other, title="More themes")
        self.assertEqual([s["title"] for s in self.board().json()], ["Dark mode"])

    def test_a_suggestion_needs_a_title_a_description_and_a_kind(self) -> None:
        self.assertEqual(self.suggest(title=" ").status_code, 422)
        self.assertEqual(self.suggest(description="").status_code, 422)
        self.assertEqual(self.suggest(kind="rant").status_code, 422)
        self.assertEqual(self.suggest(title="x" * 81).status_code, 422)

    def test_upvotes_count_once_rank_the_board_and_can_be_taken_back(self) -> None:
        first = self.suggest(SAM, title="First").json()
        second = self.suggest(SAM, title="Second").json()
        self.assertEqual(
            [s["title"] for s in self.board().json()], ["Second", "First"], "newest first"
        )
        voted = self.vote(first["id"], ADMIN)
        self.assertEqual(voted.status_code, 200, voted.text)
        self.assertEqual((voted.json()["votes"], voted.json()["voted"]), (1, True))
        self.assertEqual(self.vote(first["id"], ADMIN).json()["votes"], 1, "once")
        self.assertEqual(
            [s["title"] for s in self.board().json()], ["First", "Second"], "most upvoted first"
        )
        taken = self.vote(first["id"], ADMIN, up=False).json()
        self.assertEqual((taken["votes"], taken["voted"]), (0, False))
        self.assertEqual(self.vote(second["id"], SAM).status_code, 422, "not your own")
        self.assertEqual(self.vote(second["id"], KIM).status_code, 403)

    def test_another_servers_suggestion_cant_be_voted_on(self) -> None:
        theirs = self.suggest(KIM, self.other).json()
        self.assertEqual(self.vote(theirs["id"], ADMIN).status_code, 404)
