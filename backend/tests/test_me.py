from sqlalchemy import select

from app.models import Player
from tests.helpers import ApiTestCase, bearer, make_token


class SignupTests(ApiTestCase):
    def test_not_signed_up_until_a_first_name_is_picked(self) -> None:
        response = self.client.get("/me", headers=bearer(make_token()))
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["detail"], "Not signed up yet")

    def test_first_signup_creates_a_player_linked_to_the_auth0_account(self) -> None:
        created = self.sign_up("auth0|alex", "  Alex ")
        self.assertEqual(created["first_name"], "Alex")
        self.assertEqual(
            set(created),
            {"id", "first_name", "created_at", "can_edit_content", "tutorials_seen"},
        )
        self.assertFalse(created["can_edit_content"])
        self.assertEqual(created["tutorials_seen"], [])

        with self.session_factory() as session:
            player = session.scalar(select(Player))
        self.assertEqual(player.auth0_id, "auth0|alex")
        self.assertEqual(str(player.id), created["id"])

        response = self.client.get("/me", headers=bearer(make_token("auth0|alex")))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), created)

    def test_signing_up_again_renames_instead_of_duplicating(self) -> None:
        first = self.sign_up("auth0|alex", "Alex")
        second = self.sign_up("auth0|alex", "Alexandra")
        self.assertEqual(second["id"], first["id"])
        self.assertEqual(second["first_name"], "Alexandra")
        with self.session_factory() as session:
            self.assertEqual(len(session.scalars(select(Player)).all()), 1)

    def test_content_editors_are_told_so(self) -> None:
        self.sign_up()
        editor = make_token(permissions=["read:api", "edit:content"])
        response = self.client.get("/me", headers=bearer(editor))
        self.assertTrue(response.json()["can_edit_content"])

    def test_players_are_separated_by_auth0_account(self) -> None:
        alex = self.sign_up("auth0|alex", "Alex")
        sam = self.sign_up("google-oauth2|sam", "Sam")
        self.assertNotEqual(alex["id"], sam["id"])
        response = self.client.get("/me", headers=bearer(make_token("google-oauth2|sam")))
        self.assertEqual(response.json()["first_name"], "Sam")

    def test_first_name_is_required_and_limited(self) -> None:
        for name in ("", "   ", "x" * 51):
            response = self.client.put(
                "/me", json={"first_name": name}, headers=bearer(make_token())
            )
            self.assertEqual(response.status_code, 422, repr(name))


class TutorialTests(ApiTestCase):
    def see(self, key: str, subject: str = "auth0|alex"):
        return self.client.put(
            f"/me/tutorials/{key}", headers=bearer(make_token(subject))
        )

    def test_seen_tutorials_are_remembered_per_account(self) -> None:
        self.sign_up("auth0|alex", "Alex")
        self.sign_up("auth0|sam", "Sam")
        response = self.see("draw")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["tutorials_seen"], ["draw"])
        self.see("boost")
        # Seeing one again changes nothing.
        self.assertEqual(self.see("draw").json()["tutorials_seen"], ["draw", "boost"])

        me = self.client.get("/me", headers=bearer(make_token("auth0|alex"))).json()
        self.assertEqual(me["tutorials_seen"], ["draw", "boost"])
        sam = self.client.get("/me", headers=bearer(make_token("auth0|sam"))).json()
        self.assertEqual(sam["tutorials_seen"], [])

    def test_only_signed_up_players_and_short_lowercase_keys(self) -> None:
        self.assertEqual(self.see("draw").status_code, 404)
        self.sign_up("auth0|alex", "Alex")
        for key in ("Draw", "x" * 41, "draw_step", "draw%20it"):
            self.assertEqual(self.see(key).status_code, 422, key)
        self.assertEqual(self.see("first-day").status_code, 200)
