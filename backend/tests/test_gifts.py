from fastapi.testclient import TestClient

from tests.helpers import bearer, make_token
from tests.test_fights import ROBIN, SAM, FightTestCase
from tests.test_setup import ADMIN

SERVER_ADMIN = ["read:api", "manage:servers"]


class GiftTestCase(FightTestCase):
    """A launched test session with Alex (seat 0), Sam (1) and Robin (2)."""

    client: TestClient

    def send(self, permissions=SERVER_ADMIN, **body):
        return self.client.post(
            "/manage/gifts",
            json={"message": "Sorry for the downtime!", "pulls": 3, **body},
            headers=bearer(make_token(ADMIN, permissions=permissions)),
        )

    def gifts(self, subject: str = ADMIN):
        return self.get(f"/servers/{self.code}/gifts", subject).json()

    def accept(self, gift_id: str, subject: str = ADMIN):
        return self.client.post(
            f"/servers/{self.code}/gifts/{gift_id}/accept",
            headers=bearer(make_token(subject)),
        )

    def tickets(self, subject: str = ADMIN) -> int:
        return self.get(f"/servers/{self.code}/gacha", subject).json()["tickets"]


class GiftTests(GiftTestCase):
    def test_only_server_admins_send_gifts_and_list_servers(self) -> None:
        self.assertEqual(self.send(permissions=["read:api"]).status_code, 403)
        listing = self.client.get(
            "/manage/servers",
            headers=bearer(make_token(ADMIN, permissions=["read:api"])),
        )
        self.assertEqual(listing.status_code, 403)

    def test_servers_are_listed_with_their_players(self) -> None:
        listing = self.client.get(
            "/manage/servers",
            headers=bearer(make_token(ADMIN, permissions=SERVER_ADMIN)),
        ).json()
        server = next(s for s in listing if s["code"] == self.code)
        self.assertTrue(server["launched"])
        self.assertFalse(server["speed"])
        self.assertEqual(
            [(p["position"], p["joined"]) for p in server["players"]][:3],
            [(0, True), (1, True), (2, True)],
        )

    def test_a_gift_counts_once_accepted_and_only_once(self) -> None:
        sent = self.send(server_code=self.code)
        self.assertEqual(sent.status_code, 201, sent.text)
        self.assertGreaterEqual(sent.json()["recipients"], 3, "everyone on the server")
        before = self.tickets(SAM)
        [gift] = self.gifts(SAM)
        self.assertEqual(
            (gift["message"], gift["pulls"]), ("Sorry for the downtime!", 3)
        )
        self.assertEqual(self.tickets(SAM), before, "not before it's accepted")

        accepted = self.accept(gift["id"], SAM)
        self.assertEqual(accepted.status_code, 200, accepted.text)
        self.assertEqual(accepted.json(), [], "nothing left waiting")
        self.assertEqual(self.tickets(SAM), before + 3)
        # Again: nothing more.
        self.assertEqual(self.accept(gift["id"], SAM).status_code, 200)
        self.assertEqual(self.tickets(SAM), before + 3)
        # The others' still wait.
        self.assertEqual(len(self.gifts(ROBIN)), 1)

    def test_a_gift_to_chosen_players(self) -> None:
        sent = self.send(server_code=self.code, positions=[1])
        self.assertEqual(sent.json()["recipients"], 1)
        self.assertEqual(len(self.gifts(SAM)), 1)
        self.assertEqual(self.gifts(ROBIN), [])
        self.assertEqual(self.gifts(ADMIN), [])

    def test_a_gift_to_every_server(self) -> None:
        other = self.create().json()["code"]
        sent = self.send()
        self.assertEqual(sent.status_code, 201, sent.text)
        listing = self.client.get(
            "/manage/servers",
            headers=bearer(make_token(ADMIN, permissions=SERVER_ADMIN)),
        ).json()
        seats = sum(len(s["players"]) for s in listing)
        self.assertEqual(sent.json()["recipients"], seats, "every seat of every server")
        self.assertIn(other, {s["code"] for s in listing})
        self.assertEqual(len(self.gifts(ROBIN)), 1)

    def test_gifts_wait_in_order_and_are_your_own(self) -> None:
        self.send(server_code=self.code, message="First", positions=[1])
        self.send(server_code=self.code, message="Second", positions=[1])
        self.assertEqual([g["message"] for g in self.gifts(SAM)], ["First", "Second"])
        first = self.gifts(SAM)[0]["id"]
        self.assertEqual(self.accept(first, ROBIN).status_code, 404, "not Robin's")

    def test_invalid_gifts_are_refused(self) -> None:
        cases = [
            ({"positions": [1]}, "a server is needed for chosen players"),
            ({"server_code": "999999"}, "no such server"),
            ({"server_code": None, "pulls": 0}, "at least one pull"),
            ({"server_code": None, "message": "   "}, "a message"),
        ]
        for body, reason in cases:
            self.assertIn(self.send(**body).status_code, (404, 422), reason)
        unknown = self.send(server_code=self.code, positions=[42])
        self.assertEqual(unknown.status_code, 422)
        self.assertEqual(
            unknown.json()["detail"], "No player at position 42 on this server"
        )
