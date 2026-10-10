import os
import unittest
from typing import Annotated
from unittest.mock import patch

from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from app.auth import get_auth0_subject
from app.docs_login import configure_docs_login

SETTINGS = {
    "AUTH0_DOMAIN": "tenant.example.auth0.com",
    "AUTH0_AUDIENCE": "https://api.drawing-duel.example",
    "AUTH0_DOCS_CLIENT_ID": "docs-client",
}


def docs_app(settings: dict[str, str]) -> TestClient:
    application = FastAPI()

    @application.get("/health")
    def health() -> dict:
        return {}

    @application.get("/private")
    def private(subject: Annotated[str, Depends(get_auth0_subject)]) -> str:
        return subject

    with patch.dict(os.environ, settings, clear=True):
        configure_docs_login(application)
    return TestClient(application)


class DocsLoginTests(unittest.TestCase):
    def test_the_docs_sign_in_with_auth0(self) -> None:
        client = docs_app(SETTINGS)
        schema = client.get("/openapi.json").json()
        flow = schema["components"]["securitySchemes"]["Auth0"]["flows"][
            "authorizationCode"
        ]
        self.assertEqual(
            flow["authorizationUrl"], "https://tenant.example.auth0.com/authorize"
        )
        self.assertEqual(
            flow["tokenUrl"], "https://tenant.example.auth0.com/oauth/token"
        )
        self.assertEqual(
            schema["paths"]["/private"]["get"]["security"],
            [{"HTTPBearer": []}, {"Auth0": []}],
            "a pasted token still works",
        )
        self.assertNotIn("security", schema["paths"]["/health"]["get"])
        self.assertEqual(client.get("/openapi.json").json(), schema)

        docs = client.get("/docs").text
        self.assertIn('"clientId": "docs-client"', docs)
        self.assertIn('"usePkceWithAuthorizationCodeGrant": true', docs)
        self.assertIn('"audience": "https://api.drawing-duel.example"', docs)
        self.assertIn('"response_mode": "form_post"', docs)

    def test_the_posted_login_moves_to_the_url_fragment(self) -> None:
        client = docs_app(SETTINGS)
        response = client.post(
            "/docs/oauth2-redirect",
            data={"code": "abc", "state": "U2F0="},
            follow_redirects=False,
        )
        self.assertEqual(response.status_code, 303)
        self.assertEqual(
            response.headers["location"], "/docs/oauth2-redirect#code=abc&state=U2F0%3D"
        )
        self.assertEqual(client.get("/docs/oauth2-redirect").status_code, 200)

    def test_without_a_docs_client_the_docs_take_a_pasted_token(self) -> None:
        settings = {k: v for k, v in SETTINGS.items() if k != "AUTH0_DOCS_CLIENT_ID"}
        client = docs_app(settings)
        schema = client.get("/openapi.json").json()
        self.assertNotIn("Auth0", schema["components"]["securitySchemes"])
        self.assertNotIn("clientId", client.get("/docs").text)
        self.assertEqual(client.post("/docs/oauth2-redirect").status_code, 405)
