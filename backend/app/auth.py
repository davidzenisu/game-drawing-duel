"""Authentication with Auth0 access tokens.

Every route except the health check and the API docs requires a valid access
token for the configured Auth0 API (see `AUTH0_DOMAIN` and `AUTH0_AUDIENCE`).
"""

import os
from collections.abc import Callable
from functools import lru_cache
from typing import Annotated, Any

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Player

ALGORITHMS = ["RS256"]


class TokenVerifier:
    """Verifies Auth0 access tokens: signature, expiry, issuer and audience."""

    def __init__(
        self,
        issuer: str,
        audience: str,
        signing_key: Callable[[str], Any],
    ) -> None:
        self.issuer = issuer
        self.audience = audience
        self._signing_key = signing_key

    @classmethod
    def for_auth0(cls, domain: str, audience: str) -> "TokenVerifier":
        issuer = f"https://{domain}/"
        jwks = jwt.PyJWKClient(f"{issuer}.well-known/jwks.json", cache_keys=True)
        return cls(
            issuer,
            audience,
            lambda token: jwks.get_signing_key_from_jwt(token).key,
        )

    def verify(self, token: str) -> dict[str, Any]:
        return jwt.decode(
            token,
            self._signing_key(token),
            algorithms=ALGORITHMS,
            audience=self.audience,
            issuer=self.issuer,
            options={"require": ["exp", "iat", "sub"]},
        )


@lru_cache
def _verifier_for(domain: str, audience: str) -> TokenVerifier:
    return TokenVerifier.for_auth0(domain, audience)


def get_token_verifier() -> TokenVerifier:
    domain = os.getenv("AUTH0_DOMAIN")
    audience = os.getenv("AUTH0_AUDIENCE")
    if not domain or not audience:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication is not configured",
        )
    return _verifier_for(domain, audience)


_bearer = HTTPBearer(auto_error=False)


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_auth0_subject(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    verifier: Annotated[TokenVerifier, Depends(get_token_verifier)],
) -> str:
    """The Auth0 user id of the caller, from a verified access token."""
    if credentials is None:
        raise _unauthorized("Not authenticated")
    try:
        claims = verifier.verify(credentials.credentials)
    except jwt.PyJWKClientConnectionError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not reach the authentication provider",
        ) from error
    except jwt.PyJWTError as error:
        raise _unauthorized("Invalid access token") from error
    return claims["sub"]


Auth0Subject = Annotated[str, Depends(get_auth0_subject)]


def get_current_player(
    subject: Auth0Subject,
    session: Annotated[Session, Depends(get_db)],
) -> Player:
    """The signed-in player's record, loaded for every request that needs it."""
    player = session.scalar(select(Player).where(Player.auth0_id == subject))
    if player is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Finish signing up first",
        )
    return player


CurrentPlayer = Annotated[Player, Depends(get_current_player)]
