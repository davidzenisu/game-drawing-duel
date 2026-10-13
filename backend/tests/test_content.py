from datetime import UTC, datetime

from app import days
from app.models import Server, ThemeHint
from app.rules import Theme
from tests.helpers import ApiTestCase, bearer, make_token

EDITOR = ["read:api", "edit:content"]


class ContentTestCase(ApiTestCase):
    def request(self, method: str, path: str, permissions=EDITOR, json=None):
        return self.client.request(
            method,
            f"/content/{path}",
            json=json,
            headers=bearer(make_token(permissions=permissions)),
        )

    def add(self, theme: str, hints: list[tuple[str, str]]):
        return self.request(
            "POST",
            "hints",
            json={
                "theme": theme,
                "hints": [{"text": t, "premade_title": p} for t, p in hints],
            },
        )


class ContentPermissionTests(ContentTestCase):
    def test_only_content_editors(self) -> None:
        self.assertEqual(self.client.get("/content/hints").status_code, 401)
        player = self.request("GET", "hints", permissions=["read:api"])
        self.assertEqual(player.status_code, 403)
        self.assertEqual(player.json()["detail"], "Missing permission edit:content")
        only_content = self.request("GET", "hints", permissions=["edit:content"])
        self.assertEqual(only_content.status_code, 403)
        self.assertEqual(only_content.json()["detail"], "Missing permission read:api")
        self.assertEqual(self.request("GET", "hints").status_code, 200)
        for method, path in (
            ("POST", "hints"),
            ("DELETE", "hints/00000000-0000-0000-0000-000000000000"),
        ):
            response = self.request(method, path, permissions=["read:api"])
            self.assertEqual(response.status_code, 403, path)


class ContentTests(ContentTestCase):
    def test_hints_come_with_a_premade_title_once_per_theme(self) -> None:
        response = self.add(
            "volcano",
            [
                (" a sauna regular ", " Lord of the Top Bench "),
                ("a toast burner", "The Toast Incinerator"),
                ("A Sauna Regular", "Another"),
            ],
        )
        self.assertEqual(response.status_code, 201, response.text)
        added = response.json()
        self.assertEqual(
            [(h["text"], h["premade_title"]) for h in added["added"]],
            [
                ("a sauna regular", "Lord of the Top Bench"),
                ("a toast burner", "The Toast Incinerator"),
            ],
        )
        self.assertEqual(added["skipped"], ["A Sauna Regular"])

        again = self.add("volcano", [("a toast burner", "X"), ("a chili lover", "Y")])
        self.assertEqual(again.json()["skipped"], ["a toast burner"])
        # The same description is fine in another theme.
        self.add("snow", [("a toast burner", "Frozen Toast")])

        volcano = self.request("GET", "hints?theme=volcano").json()
        self.assertEqual(
            [h["text"] for h in volcano],
            ["a sauna regular", "a toast burner", "a chili lover"],
        )
        self.assertEqual({h["theme"] for h in volcano}, {"volcano"})
        self.assertEqual(len(self.request("GET", "hints").json()), 4)

    def test_rejects_unknown_themes_and_empty_or_long_titles(self) -> None:
        self.assertEqual(self.add("moon", [("a", "b")]).status_code, 422)
        self.assertEqual(self.add("volcano", []).status_code, 422)
        self.assertEqual(self.add("volcano", [("ok", "ok"), ("  ", "t")]).status_code, 422)
        self.assertEqual(self.add("volcano", [("ok", "  ")]).status_code, 422)
        self.assertEqual(self.add("volcano", [("ok", "x" * 61)]).status_code, 422)
        self.assertEqual(self.add("volcano", [("x" * 61, "ok")]).status_code, 201)
        self.assertEqual(self.request("GET", "hints?theme=moon").status_code, 422)
        self.assertEqual(self.request("GET", "premade-titles").status_code, 404)

    def test_retired_hints_are_not_listed_and_can_be_added_again(self) -> None:
        [hint] = self.add("castle", [("a couch king", "The Couch King")]).json()["added"]
        path = f"hints/{hint['id']}"
        self.assertEqual(self.request("DELETE", path).status_code, 204)
        self.assertEqual(self.request("GET", "hints").json(), [])
        again = self.request("DELETE", path)
        self.assertEqual(again.status_code, 404)
        self.assertEqual(again.json()["detail"], "No such hint")
        self.assertEqual(
            self.add("castle", [("a couch king", "The Couch King")]).json()["skipped"],
            [],
        )

    def test_a_retired_hint_is_used_until_the_end_of_the_day(self) -> None:
        with self.session_factory() as session:
            hint = ThemeHint(
                theme="volcano",
                text="a sauna regular",
                premade_title="Lord of the Top Bench",
                created_at=datetime(2026, 1, 1, tzinfo=UTC),
            )
            session.add(hint)
            session.commit()
            hint_id = hint.id
        self.assertEqual(self.request("DELETE", f"hints/{hint_id}").status_code, 204)

        # A server whose day 1 is today, when the hint was retired.
        server = Server(is_test=False, launched_at=datetime.now(UTC))
        with self.session_factory() as session:
            today, tomorrow = (
                [h.text for h in days.hints_on(session, server, day, Theme.VOLCANO)]
                for day in (1, 2)
            )
        self.assertEqual(today, ["a sauna regular"])
        self.assertEqual(tomorrow, [])
