import time
import unittest
from typing import Any

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.auth import TokenVerifier, get_token_verifier
from app.database import Base, get_db
from app.main import app

ISSUER = "https://tenant.example.auth0.com/"
AUDIENCE = "https://api.drawing-duel.example"

_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


def make_token(
    subject: str = "auth0|alex",
    *,
    audience: str = AUDIENCE,
    issuer: str = ISSUER,
    expires_in: int = 3600,
    signed_by_other_key: bool = False,
    **claims: Any,
) -> str:
    now = int(time.time())
    payload = {
        "sub": subject,
        "aud": audience,
        "iss": issuer,
        "iat": now,
        "exp": now + expires_in,
        **claims,
    }
    key = _OTHER_KEY if signed_by_other_key else _KEY
    return jwt.encode(payload, key, algorithm="RS256")


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


class ApiTestCase(unittest.TestCase):
    """Runs the API against an in-memory database, trusting the test key."""

    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.session_factory = sessionmaker(bind=self.engine, expire_on_commit=False)

        def override_get_db():
            with self.session_factory() as session:
                yield session

        public_key = _KEY.public_key()
        app.dependency_overrides[get_db] = override_get_db
        app.dependency_overrides[get_token_verifier] = lambda: TokenVerifier(
            ISSUER, AUDIENCE, lambda _token: public_key
        )
        self.client = TestClient(app)

    def tearDown(self) -> None:
        app.dependency_overrides.clear()
        self.engine.dispose()

    def sign_up(self, subject: str = "auth0|alex", first_name: str = "Alex") -> dict:
        response = self.client.put(
            "/me", json={"first_name": first_name}, headers=bearer(make_token(subject))
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()
