import os
import re
from unittest.mock import patch

from app.auth import get_token_verifier
from app.main import app
from tests.helpers import ApiTestCase, bearer, make_token

PUBLIC_PATHS = {"/health"}


class AuthenticationTests(ApiTestCase):
    def test_every_route_except_health_and_docs_requires_a_token(self) -> None:
        # The OpenAPI schema lists every API route, including included routers.
        paths = app.openapi()["paths"]
        protected = {path: ops for path, ops in paths.items() if path not in PUBLIC_PATHS}
        self.assertIn("/me", protected)
        for path, operations in protected.items():
            url = re.sub(r"\{[^}]+\}", "1", path)
            for method in operations:
                response = self.client.request(method.upper(), url)
                self.assertEqual(
                    response.status_code, 401, f"{method.upper()} {path} is not protected"
                )
                self.assertEqual(response.headers["www-authenticate"], "Bearer")

    def test_docs_stay_public(self) -> None:
        for path in ("/openapi.json", "/docs", "/redoc"):
            self.assertEqual(self.client.get(path).status_code, 200, path)

    def test_rejects_invalid_tokens(self) -> None:
        cases = {
            "garbage": "not-a-token",
            "wrong signature": make_token(signed_by_other_key=True),
            "expired": make_token(expires_in=-60),
            "wrong audience": make_token(audience="https://other.example"),
            "wrong issuer": make_token(issuer="https://evil.example/"),
        }
        for name, token in cases.items():
            response = self.client.get("/me", headers=bearer(token))
            self.assertEqual(response.status_code, 401, name)
            self.assertEqual(response.json()["detail"], "Invalid access token", name)

    def test_accepts_a_valid_token(self) -> None:
        response = self.client.get("/me", headers=bearer(make_token()))
        # Authenticated, but not signed up yet.
        self.assertEqual(response.status_code, 404)

    def test_service_unavailable_without_auth0_configuration(self) -> None:
        del app.dependency_overrides[get_token_verifier]
        with patch.dict(os.environ, {}, clear=True):
            response = self.client.get("/me", headers=bearer(make_token()))
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["detail"], "Authentication is not configured")
