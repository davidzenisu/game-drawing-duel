import json
import uuid

from app.main import app
from app.storage import StorageUnavailable, get_file_store
from tests.helpers import bearer, make_token
from tests.test_setup import ADMIN, FRIEND_SUBJECTS, SetupTestCase

SKETCH = {
    "strokes": [
        {"color": 0xFF000000, "width": 0.016, "points": [0.1, 0.2, 0.3, 0.4]},
        {"color": 0xFFE53935, "width": 0.035, "points": [0.5, 0.5, 1.0, 0.0]},
    ]
}


class FailingFileStore:
    def upload(self, *args, **kwargs) -> None:
        raise StorageUnavailable("down")

    def download(self, name: str) -> bytes:
        raise StorageUnavailable("down")

    def delete(self, name: str) -> None:
        raise StorageUnavailable("down")


class DrawingUploadTests(SetupTestCase):
    def setUp(self) -> None:
        super().setUp()
        # A test session with Alex alone: Basic, Knight and Legend of others.
        self.code = self.create(is_test=True).json()["code"]
        self.start(self.code)
        self.by_prompt = {a["prompt"]: a for a in self.assignments(self.code).json()}

    def draw(
        self, assignment_id: int, title="The early years", sketch=SKETCH, subject=ADMIN
    ):
        return self.client.put(
            f"/servers/{self.code}/assignments/{assignment_id}/drawing",
            json={"title": title, "sketch": sketch},
            headers=bearer(make_token(subject)),
        )

    def sketch(self, character_id: str, subject: str = ADMIN):
        return self.client.get(
            f"/characters/{character_id}/sketch", headers=bearer(make_token(subject))
        )

    def test_a_drawing_is_stored_as_a_file_named_after_its_character(self) -> None:
        response = self.draw(self.by_prompt["knight"]["id"], "  Sir Alex ")
        self.assertEqual(response.status_code, 200, response.text)
        character = response.json()
        self.assertEqual(character["title"], "Sir Alex")
        self.assertEqual(character["rarity"], "adventurer")
        self.assertEqual(character["prompt"], "knight")
        self.assertEqual(
            (character["artist_position"], character["subject_position"]),
            (0, self.by_prompt["knight"]["subject_position"]),
        )

        data, content_type, metadata = self.files.files[character["id"]]
        self.assertEqual(json.loads(data), SKETCH)
        self.assertEqual(content_type, "application/json")
        self.assertEqual(
            metadata,
            {
                "kind": "setup",
                "server": self.code,
                "prompt": "knight",
                "rarity": "adventurer",
                "artist_position": "0",
                "subject_position": str(self.by_prompt["knight"]["subject_position"]),
            },
        )

        listed = {a["prompt"]: a for a in self.assignments(self.code).json()}
        self.assertEqual(listed["knight"]["character"], character)
        self.assertIsNone(listed["basic"]["character"])

    def test_redrawing_replaces_the_character_and_its_file(self) -> None:
        first = self.draw(self.by_prompt["basic"]["id"]).json()
        second = self.draw(self.by_prompt["basic"]["id"], "Again").json()
        self.assertNotEqual(first["id"], second["id"])
        self.assertEqual(list(self.files.files), [second["id"]])
        listed = {a["prompt"]: a for a in self.assignments(self.code).json()}
        self.assertEqual(listed["basic"]["character"]["title"], "Again")

    def test_players_of_the_server_load_the_sketch(self) -> None:
        character = self.draw(self.by_prompt["legend"]["id"]).json()
        response = self.sketch(character["id"])
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json(), SKETCH)
        self.assertIn("immutable", response.headers["cache-control"])

        self.sign_up("auth0|stranger", "Pat")
        response = self.sketch(character["id"], "auth0|stranger")
        self.assertEqual(response.status_code, 404)

        del self.files.files[character["id"]]
        self.assertEqual(
            self.sketch(character["id"]).json()["detail"], "The drawing is missing"
        )

    def test_you_only_draw_your_own_assignments(self) -> None:
        self.sign_up(FRIEND_SUBJECTS[0], "Sam")
        self.claim(self.code, 1, FRIEND_SUBJECTS[0])
        response = self.draw(self.by_prompt["basic"]["id"], subject=FRIEND_SUBJECTS[0])
        self.assertEqual(response.status_code, 404)
        self.sign_up("auth0|stranger", "Pat")
        response = self.draw(self.by_prompt["basic"]["id"], subject="auth0|stranger")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.files.files, {})

    def test_bad_drawings_are_rejected(self) -> None:
        stroke = SKETCH["strokes"][0]
        bad = [
            ("", SKETCH),
            ("x" * 61, SKETCH),
            ("Title", {"strokes": []}),
            ("Title", {"strokes": [{**stroke, "points": [0.1, 0.2, 0.3]}]}),
            ("Title", {"strokes": [{**stroke, "points": [0.1, 1.5]}]}),
            ("Title", {"strokes": [{**stroke, "width": 0}]}),
        ]
        for title, sketch in bad:
            with self.subTest(title=title, sketch=sketch):
                response = self.draw(self.by_prompt["basic"]["id"], title, sketch)
                self.assertEqual(response.status_code, 422)
        self.assertEqual(self.files.files, {})

    def test_a_storage_failure_stores_nothing(self) -> None:
        app.dependency_overrides[get_file_store] = FailingFileStore
        response = self.draw(self.by_prompt["basic"]["id"])
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["detail"], "Couldn't store the drawing")
        self.assertIsNone(self.assignments(self.code).json()[0]["character"])

    def test_storage_needs_configuration(self) -> None:
        del app.dependency_overrides[get_file_store]
        response = self.draw(self.by_prompt["basic"]["id"])
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["detail"], "Storage is not configured")


class AlterTests(SetupTestCase):
    def test_the_alter_waits_for_its_basic(self) -> None:
        code = self.create().json()["code"]
        self.join_everyone(code)
        self.start(code)
        by_prompt = {a["prompt"]: a for a in self.assignments(code).json()}

        def draw(prompt: str):
            return self.client.put(
                f"/servers/{code}/assignments/{by_prompt[prompt]['id']}/drawing",
                json={"title": prompt, "sketch": SKETCH},
                headers=bearer(make_token(ADMIN)),
            )

        response = draw("alter")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(
            response.json()["detail"], "Draw the drawing this one is based on first"
        )
        self.assertEqual(draw("basic").status_code, 200)
        self.assertEqual(draw("alter").status_code, 200)

    def test_drawing_waits_for_the_setup(self) -> None:
        code = self.create().json()["code"]
        response = self.client.put(
            f"/servers/{code}/assignments/{uuid.uuid4()}/drawing",
            json={"title": "Too early", "sketch": SKETCH},
            headers=bearer(make_token(ADMIN)),
        )
        self.assertEqual(response.status_code, 409)
