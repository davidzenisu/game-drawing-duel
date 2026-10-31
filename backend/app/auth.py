"""Authentication with Auth0 access tokens.

Every route except the health check and the API docs requires a valid access
token for the configured Auth0 API (see `AUTH0_DOMAIN` and `AUTH0_AUDIENCE`)
that carries the player permission. Auth0 grants it through the `user` role and
adds it to the `permissions` claim (RBAC with "Add Permissions in the Access
Token" enabled on the API).

The content routes also need `edit:content`, for the accounts that manage the
prompt hints and premade titles (see `require_content_editor`), and the admin
routes `manage:servers` (see `require_server_admin`).
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

# Every player has it; tokens without it (e.g. machine-to-machine) are rejected.
REQUIRED_PERMISSION = "read:api"
# For the accounts that manage the prompt hints and premade titles.
CONTENT_PERMISSION = "edit:content"

# For the accounts that clean up servers (`app.routers.admin`).
ADMIN_PERMISSION = "manage:servers"


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
    def for_auth0(cls, domain: str, audience: str) -> TokenVerifier:
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


def _forbidden(permission: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail=f"Missing permission {permission}",
        headers={"WWW-Authenticate": 'Bearer error="insufficient_scope"'},
    )


def get_token_claims(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    verifier: Annotated[TokenVerifier, Depends(get_token_verifier)],
) -> dict[str, Any]:
    """The claims of the caller's verified access token, which carries the
    player permission."""
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
    permissions = claims.get("permissions")
    if not isinstance(permissions, list) or REQUIRED_PERMISSION not in permissions:
        raise _forbidden(REQUIRED_PERMISSION)
    return claims


TokenClaims = Annotated[dict[str, Any], Depends(get_token_claims)]


def get_auth0_subject(claims: TokenClaims) -> str:
    """The Auth0 user id of the caller, from a verified access token."""
    return claims["sub"]


def require_content_editor(claims: TokenClaims) -> None:
    """Lets only accounts with the content permission through."""
    if CONTENT_PERMISSION not in claims["permissions"]:
        raise _forbidden(CONTENT_PERMISSION)


def require_server_admin(claims: TokenClaims) -> None:
    """Lets only accounts with the admin permission through."""
    if ADMIN_PERMISSION not in claims["permissions"]:
        raise _forbidden(ADMIN_PERMISSION)


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
