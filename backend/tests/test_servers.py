import re
from unittest.mock import patch

from app.routers import servers
from tests.helpers import ApiTestCase, bearer, make_token

ADMIN = "auth0|alex"
FRIENDS = ["Sam", "Robin", "Kim", "Jo"]


class ServerTestCase(ApiTestCase):
    """Signs up the admin; helpers to create and join servers."""

    def setUp(self) -> None:
        super().setUp()
        self.sign_up(ADMIN, "Alex")

    def create(
        self,
        names: list[str] | None = None,
        subject: str = ADMIN,
        *,
        is_test: bool | None = None,
    ):
        body: dict = {"other_names": FRIENDS if names is None else names}
        if is_test is not None:
            body["is_test"] = is_test
        return self.client.post(
            "/servers", json=body, headers=bearer(make_token(subject))
        )

    def claim(self, code: str, position: int, subject: str):
        return self.client.post(
            f"/servers/{code}/seats/{position}/claim",
            headers=bearer(make_token(subject)),
        )


class ServerTests(ServerTestCase):
    def test_creating_a_server_generates_a_code_and_seats_the_admin(self) -> None:
        response = self.create()
        self.assertEqual(response.status_code, 201, response.text)
        server = response.json()
        self.assertRegex(server["code"], r"^\d{6}$")
        self.assertTrue(server["is_admin"])
        self.assertEqual(server["phase"], "lobby")
        self.assertEqual(server["your_position"], 0)
        self.assertEqual(
            [(s["position"], s["name"], s["joined"]) for s in server["seats"]],
            [(0, "Alex", True)] + [(i + 1, n, False) for i, n in enumerate(FRIENDS)],
        )

    def test_servers_are_regular_unless_marked_as_test_sessions(self) -> None:
        self.assertFalse(self.create().json()["is_test"])
        test_server = self.create(is_test=True).json()
        self.assertTrue(test_server["is_test"])
        self.sign_up("auth0|sam", "Sam")
        seen_by_sam = self.client.get(
            f"/servers/{test_server['code']}", headers=bearer(make_token("auth0|sam"))
        )
        self.assertTrue(seen_by_sam.json()["is_test"])

    def test_rosters_need_five_to_ten_players_with_different_names(self) -> None:
        for names in (FRIENDS[:3], [f"P{i}" for i in range(10)]):
            self.assertEqual(self.create(names).status_code, 422, len(names))
        duplicate = self.create(["Sam", "sam", "Kim", "Jo"])
        self.assertEqual(duplicate.status_code, 422)
        self.assertEqual(
            duplicate.json()["detail"], "Every player needs a different name"
        )
        clash_with_admin = self.create(["ALEX", "Sam", "Kim", "Jo"])
        self.assertEqual(clash_with_admin.status_code, 422)
        self.assertEqual(self.create([" ", "Sam", "Kim", "Jo"]).status_code, 422)

    def test_a_taken_code_is_retried(self) -> None:
        first = self.create().json()["code"]
        codes = iter([first, first, "424242"])
        with patch.object(servers, "_new_code", lambda: next(codes)):
            response = self.create()
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["code"], "424242")

    def test_friends_preview_the_roster_and_claim_their_seat(self) -> None:
        code = self.create().json()["code"]
        self.sign_up("auth0|sam", "Sam")

        preview = self.client.get(
            f"/servers/{code}", headers=bearer(make_token("auth0|sam"))
        )
        self.assertEqual(preview.status_code, 200)
        self.assertFalse(preview.json()["is_admin"])
        self.assertIsNone(preview.json()["your_position"])

        joined = self.claim(code, 1, "auth0|sam")
        self.assertEqual(joined.status_code, 200, joined.text)
        self.assertEqual(joined.json()["your_position"], 1)
        self.assertTrue(joined.json()["seats"][1]["joined"])

        # Claiming your own seat again is fine.
        self.assertEqual(self.claim(code, 1, "auth0|sam").status_code, 200)
        # The admin sees Sam joined.
        lobby = self.client.get(f"/servers/{code}", headers=bearer(make_token(ADMIN)))
        self.assertEqual(
            [s["joined"] for s in lobby.json()["seats"]], [True, True] + [False] * 3
        )

    def test_seats_can_only_be_claimed_once(self) -> None:
        code = self.create().json()["code"]
        self.sign_up("auth0|sam", "Sam")
        self.sign_up("auth0|kim", "Kim")
        self.claim(code, 1, "auth0|sam")

        taken = self.claim(code, 1, "auth0|kim")
        self.assertEqual(taken.status_code, 409)
        self.assertEqual(taken.json()["detail"], "This seat is taken")
        admin_seat = self.claim(code, 0, "auth0|kim")
        self.assertEqual(admin_seat.status_code, 409)
        second_seat = self.claim(code, 2, "auth0|sam")
        self.assertEqual(second_seat.status_code, 409)
        self.assertEqual(second_seat.json()["detail"], "You already joined this server")

    def test_unknown_servers_and_seats(self) -> None:
        code = self.create().json()["code"]
        other = "000000" if code != "000000" else "111111"
        headers = bearer(make_token(ADMIN))
        self.assertEqual(
            self.client.get(f"/servers/{other}", headers=headers).status_code, 404
        )
        self.assertEqual(
            self.client.get("/servers/12345", headers=headers).status_code, 422
        )
        self.assertEqual(self.claim(code, 99, ADMIN).status_code, 404)

    def test_my_servers_lists_the_servers_you_joined_newest_first(self) -> None:
        first = self.create().json()["code"]
        second = self.create().json()["code"]
        self.sign_up("auth0|sam", "Sam")
        self.claim(first, 1, "auth0|sam")

        mine = self.client.get("/servers/mine", headers=bearer(make_token(ADMIN)))
        self.assertEqual([s["code"] for s in mine.json()], [second, first])
        sams = self.client.get("/servers/mine", headers=bearer(make_token("auth0|sam")))
        self.assertEqual([s["code"] for s in sams.json()], [first])

    def test_responses_never_expose_player_ids(self) -> None:
        body = self.create().text
        self.assertNotIn("auth0|", body)
        self.assertIsNone(re.search(r'"player_id"', body))

    def test_requires_a_signed_up_player(self) -> None:
        response = self.client.post(
            "/servers",
            json={"other_names": FRIENDS},
            headers=bearer(make_token("auth0|stranger")),
        )
        self.assertEqual(response.status_code, 403)
