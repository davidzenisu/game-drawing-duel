import os
import tempfile
from pathlib import Path
from unittest.mock import patch

from sqlalchemy.exc import OperationalError

from app import main
from app.database import get_db
from app.main import app
from tests.helpers import ApiTestCase


class HealthTests(ApiTestCase):
    def test_reports_ok_when_the_database_answers(self) -> None:
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(), {"status": "ok", "database": "ok", "version": "dev"}
        )

    def test_reports_unavailable_when_the_database_fails(self) -> None:
        class BrokenSession:
            def execute(self, *_args, **_kwargs):
                raise OperationalError("SELECT 1", {}, Exception("connection refused"))

        app.dependency_overrides[get_db] = lambda: BrokenSession()
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(
            response.json(),
            {"status": "error", "database": "unavailable", "version": "dev"},
        )

    def test_reports_unavailable_without_database_url(self) -> None:
        del app.dependency_overrides[get_db]
        with patch.dict(os.environ, {}, clear=True):
            response = self.client.get("/health")
        self.assertEqual(response.status_code, 503)

    def test_needs_no_token(self) -> None:
        self.assertNotEqual(self.client.get("/health").status_code, 401)

    def test_reports_the_deployed_commit(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            commit_file = Path(folder) / "commit.txt"
            commit_file.write_text("abc123\n")
            with patch.object(main, "COMMIT_FILE", commit_file):
                response = self.client.get("/health")
        self.assertEqual(response.json()["version"], "abc123")
