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

    def remove(self, suggestion_id: str, subject: str, permissions=None):
        return self.client.delete(
            f"/servers/{self.code}/suggestions/{suggestion_id}",
            headers=bearer(make_token(subject, permissions=permissions)),
        )

    def test_authors_remove_their_own_and_server_admins_any(self) -> None:
        mine = self.suggest(SAM, title="Mine").json()
        theirs = self.suggest(title="Alex's").json()
        self.vote(theirs["id"], SAM)
        self.assertEqual(
            {s["title"]: s["removable"] for s in self.board(SAM).json()},
            {"Mine": True, "Alex's": False},
        )
        self.assertEqual(self.remove(theirs["id"], SAM).status_code, 403)
        self.assertEqual(self.remove(mine["id"], SAM).status_code, 204)
        self.assertEqual([s["title"] for s in self.board().json()], ["Alex's"])

        # Sam, as a server admin, removes Alex's too, with its upvote.
        admin = ["read:api", "manage:servers"]
        listed = self.client.get(
            f"/servers/{self.code}/suggestions",
            headers=bearer(make_token(SAM, permissions=admin)),
        ).json()
        self.assertTrue(listed[0]["removable"])
        self.assertEqual(self.remove(theirs["id"], SAM, admin).status_code, 204)
        self.assertEqual(self.board().json(), [])
        self.assertEqual(self.remove(theirs["id"], ADMIN).status_code, 404)

    def set_status(self, suggestion_id: str, value: str, subject: str = SAM, admin=True):
        permissions = ["read:api", "manage:servers"] if admin else None
        return self.client.put(
            f"/servers/{self.code}/suggestions/{suggestion_id}/status",
            json={"status": value},
            headers=bearer(make_token(subject, permissions=permissions)),
        )

    def confirm_fixed(self, suggestion_id: str, subject: str = ADMIN):
        return self.client.post(
            f"/servers/{self.code}/suggestions/{suggestion_id}/fixed",
            headers=bearer(make_token(subject)),
        )

    def test_suggestions_are_open_and_only_server_admins_set_their_status(self) -> None:
        idea = self.suggest().json()
        self.assertEqual(idea["status"], "open")
        self.assertEqual(self.set_status(idea["id"], "in_progress", admin=False).status_code, 403)
        for value in ("in_progress", "rejected", "in_review", "open"):
            changed = self.set_status(idea["id"], value)
            self.assertEqual(changed.status_code, 200, changed.text)
            self.assertEqual(changed.json()["status"], value)
            self.assertEqual(self.board(SAM).json()[0]["status"], value)
        self.assertEqual(self.set_status(idea["id"], "done").status_code, 422, "up to the author")
        self.assertEqual(self.set_status(idea["id"], "closed").status_code, 422)
        theirs = self.suggest(KIM, self.other).json()
        self.assertEqual(self.set_status(theirs["id"], "in_review").status_code, 404)

    def test_the_author_confirms_a_fix_in_review_and_gets_a_pull_once(self) -> None:
        from app.models import Gift, GiftDelivery, ServerSeat
        from app.routers.suggestions import fixed_message

        idea = self.suggest(title="Dark mode").json()
        self.assertEqual(self.confirm_fixed(idea["id"]).status_code, 409, "not in review yet")
        self.set_status(idea["id"], "in_review")
        self.assertEqual(self.confirm_fixed(idea["id"], SAM).status_code, 403, "not Sam's")

        confirmed = self.confirm_fixed(idea["id"])
        self.assertEqual(confirmed.status_code, 200, confirmed.text)
        self.assertEqual(confirmed.json()["status"], "done")
        self.assertEqual(self.confirm_fixed(idea["id"]).status_code, 409, "only once")
        self.assertEqual(self.set_status(idea["id"], "open").status_code, 409, "done stays done")

        with self.session_factory() as session:
            gifts = session.query(Gift).all()
            self.assertEqual(len(gifts), 1)
            gift = gifts[0]
            self.assertEqual(
                (gift.message, gift.pulls, gift.stars),
                ("Dark mode has been fixed. Thank you for reporting it.", 1, 0),
            )
            self.assertEqual(gift.message, fixed_message("Dark mode"))
            seats = [
                session.get(ServerSeat, d.seat_id).name
                for d in session.query(GiftDelivery).all()
            ]
        self.assertEqual(seats, ["Alex"], "only to its author")
