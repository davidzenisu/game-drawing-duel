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

    def add(self, kind: str, theme: str, texts: list[str]):
        return self.request("POST", kind, json={"theme": theme, "texts": texts})


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
            ("POST", "premade-titles"),
            ("DELETE", "hints/00000000-0000-0000-0000-000000000000"),
        ):
            response = self.request(method, path, permissions=["read:api"])
            self.assertEqual(response.status_code, 403, path)


class ContentTests(ContentTestCase):
    def test_hints_are_added_once_per_theme_and_listed(self) -> None:
        response = self.add(
            "hints",
            "volcano",
            [" a sauna regular ", "a toast burner", "A Sauna Regular"],
        )
        self.assertEqual(response.status_code, 201, response.text)
        added = response.json()
        self.assertEqual(
            [h["text"] for h in added["added"]], ["a sauna regular", "a toast burner"]
        )
        self.assertEqual(added["skipped"], ["A Sauna Regular"])

        again = self.add("hints", "volcano", ["a toast burner", "a chili lover"])
        self.assertEqual(again.json()["skipped"], ["a toast burner"])
        # The same text is fine in another theme.
        self.add("hints", "snow", ["a toast burner"])

        volcano = self.request("GET", "hints?theme=volcano").json()
        self.assertEqual(
            [h["text"] for h in volcano],
            ["a sauna regular", "a toast burner", "a chili lover"],
        )
        self.assertEqual({h["theme"] for h in volcano}, {"volcano"})
        self.assertEqual(len(self.request("GET", "hints").json()), 4)

    def test_rejects_unknown_themes_empty_and_long_titles(self) -> None:
        self.assertEqual(self.add("hints", "moon", ["a"]).status_code, 422)
        self.assertEqual(self.add("hints", "volcano", []).status_code, 422)
        empty = self.add("hints", "volcano", ["ok", "  "])
        self.assertEqual(empty.status_code, 422)
        self.assertEqual(empty.json()["detail"], "A hint can't be empty")
        long = self.add("premade-titles", "volcano", ["x" * 61])
        self.assertEqual(long.status_code, 422)
        self.assertEqual(
            long.json()["detail"], "A premade title has at most 60 characters"
        )
        self.assertEqual(self.add("hints", "volcano", ["x" * 61]).status_code, 201)
        self.assertEqual(self.request("GET", "hints?theme=moon").status_code, 422)
        self.assertEqual(self.request("GET", "premade-titles").json(), [])

    def test_retired_titles_are_not_listed_and_can_be_added_again(self) -> None:
        [title] = self.add("premade-titles", "castle", ["The Couch King"]).json()[
            "added"
        ]
        path = f"premade-titles/{title['id']}"
        self.assertEqual(self.request("DELETE", path).status_code, 204)
        self.assertEqual(self.request("GET", "premade-titles").json(), [])
        again = self.request("DELETE", path)
        self.assertEqual(again.status_code, 404)
        self.assertEqual(again.json()["detail"], "No such premade title")
        self.assertEqual(
            self.add("premade-titles", "castle", ["The Couch King"]).json()["skipped"],
            [],
        )

    def test_a_retired_hint_is_used_until_the_end_of_the_day(self) -> None:
        with self.session_factory() as session:
            hint = ThemeHint(
                theme="volcano",
                text="a sauna regular",
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
                days._options(session, server, day, Theme.VOLCANO, ThemeHint.text)
                for day in (1, 2)
            )
        self.assertEqual(today, ["a sauna regular"])
        self.assertEqual(tomorrow, [])
