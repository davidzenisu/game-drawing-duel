from tests.helpers import bearer, make_token
from tests.test_drawing_uploads import SKETCH
from tests.test_fights import FightTestCase
from tests.test_gifts import SERVER_ADMIN
from tests.test_setup import ADMIN


class AdminDrawingTests(FightTestCase):
    """A launched test session whose three players drew a challenger on
    day 2."""

    def manage(self, path: str, permissions=SERVER_ADMIN):
        return self.client.get(
            f"/manage/{path}",
            headers=bearer(make_token(ADMIN, permissions=permissions)),
        )

    def test_only_server_admins_see_the_drawings(self) -> None:
        drawings = self.manage(f"servers/{self.code}/drawings", ["read:api"])
        self.assertEqual(drawings.status_code, 403)
        some_id = self.manage(f"servers/{self.code}/drawings").json()[0]["id"]
        sketch = self.manage(f"characters/{some_id}/sketch", ["read:api"])
        self.assertEqual(sketch.status_code, 403)

    def test_a_servers_drawings_come_setup_first_then_by_day(self) -> None:
        response = self.manage(f"servers/{self.code}/drawings")
        self.assertEqual(response.status_code, 200, response.text)
        drawings = response.json()
        setup = [d for d in drawings if d["day"] is None]
        challengers = [d for d in drawings if d["day"] is not None]
        self.assertTrue(setup)
        self.assertEqual(drawings, setup + challengers, "setup drawings first")
        self.assertTrue(all(d["date"] is None for d in setup))
        self.assertEqual([d["day"] for d in challengers], [2, 2, 2])
        self.assertEqual([d["artist"] for d in challengers], ["Alex", "Sam", "Robin"])
        self.assertEqual(len({d["date"] for d in challengers}), 1)
        self.assertEqual({d["prompt"] for d in challengers}, {"challenger"})

        self.assertEqual(self.manage("servers/000000/drawings").status_code, 404)

    def test_admins_load_any_drawing(self) -> None:
        drawing = self.manage(f"servers/{self.code}/drawings").json()[-1]
        # From any account with the permission, on the server or not.
        self.sign_up("auth0|stranger", "Pat")
        response = self.client.get(
            f"/manage/characters/{drawing['id']}/sketch",
            headers=bearer(make_token("auth0|stranger", permissions=SERVER_ADMIN)),
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json(), SKETCH)
        missing = self.manage("characters/00000000-0000-0000-0000-000000000000/sketch")
        self.assertEqual(missing.status_code, 404)
