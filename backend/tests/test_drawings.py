import os
import unittest
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.database import get_db
from app.main import app, configure_frontend_cors
from app.models import Drawing
from tests.helpers import ApiTestCase, bearer, make_token


class DrawingEndpointTests(ApiTestCase):
    def test_lists_drawings_with_timestamps(self) -> None:
        self.sign_up()
        with Session(self.engine) as session:
            session.add_all(
                [
                    Drawing(description="Second drawing"),
                    Drawing(description="First drawing"),
                ]
            )
            session.commit()

        response = self.client.get("/drawings", headers=bearer(make_token()))

        self.assertEqual(response.status_code, 200)
        drawings = response.json()
        self.assertEqual(
            [drawing["description"] for drawing in drawings],
            ["Second drawing", "First drawing"],
        )
        self.assertEqual(
            set(drawings[0]),
            {"id", "description", "created_at", "updated_at"},
        )
        self.assertTrue(drawings[0]["created_at"])
        self.assertTrue(drawings[0]["updated_at"])

    def test_requires_a_signed_up_player(self) -> None:
        response = self.client.get("/drawings", headers=bearer(make_token()))
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"], "Finish signing up first")

    def test_returns_service_unavailable_without_database_url(self) -> None:
        del app.dependency_overrides[get_db]

        with patch.dict(os.environ, {}, clear=True):
            response = self.client.get("/drawings", headers=bearer(make_token()))

        self.assertEqual(response.status_code, 503)
        self.assertEqual(
            response.json()["detail"],
            "The DATABASE_URL environment variable is not configured",
        )


class CorsTests(unittest.TestCase):
    def test_cors_uses_frontend_url_environment_variable(self) -> None:
        frontend_url = "https://frontend.example"
        cors_app = FastAPI()

        with patch.dict(os.environ, {"FRONTEND_URL": frontend_url}):
            configure_frontend_cors(cors_app)

        @cors_app.get("/resource")
        def get_resource() -> dict[str, str]:
            return {"status": "ok"}

        client = TestClient(cors_app)
        allowed_response = client.get("/resource", headers={"Origin": frontend_url})
        disallowed_response = client.get(
            "/resource", headers={"Origin": "https://other.example"}
        )

        self.assertEqual(
            allowed_response.headers.get("access-control-allow-origin"),
            frontend_url,
        )
        self.assertNotIn("access-control-allow-origin", disallowed_response.headers)
