"""Signing in to the interactive API docs (`/docs`) with Auth0.

Swagger UI's "Authorize" button runs the Auth0 login (authorization code flow
with PKCE) and sends the access token with every request, so trying the API
needs no token from elsewhere. It needs `AUTH0_DOCS_CLIENT_ID`, the client id
of an Auth0 single-page application that allows `<API URL>/docs/oauth2-redirect`
as a callback URL (see README, "API authentication"); without it the docs
only accept a pasted token.
"""

import os
from typing import Any

from fastapi import FastAPI

SCHEME = "Auth0"
_SCOPES = {
    "openid": "Sign in",
    "profile": "Your name from the login",
}


def _add_login(schema: dict[str, Any], domain: str) -> None:
    schema.setdefault("components", {}).setdefault("securitySchemes", {})[SCHEME] = {
        "type": "oauth2",
        "description": "Sign in with Auth0 like in the game.",
        "flows": {
            "authorizationCode": {
                "authorizationUrl": f"https://{domain}/authorize",
                "tokenUrl": f"https://{domain}/oauth/token",
                "scopes": _SCOPES,
            }
        },
    }
    # Every route that takes a pasted token takes the login's token too.
    for operation in (
        operation
        for path in schema.get("paths", {}).values()
        for operation in path.values()
    ):
        security = operation.get("security")
        if security and {SCHEME: []} not in security:
            security.append({SCHEME: []})


def configure_docs_login(application: FastAPI) -> None:
    """Adds the Auth0 login to the docs if `AUTH0_DOMAIN`, `AUTH0_AUDIENCE`
    and `AUTH0_DOCS_CLIENT_ID` are set."""
    domain = os.getenv("AUTH0_DOMAIN")
    audience = os.getenv("AUTH0_AUDIENCE")
    client_id = os.getenv("AUTH0_DOCS_CLIENT_ID")
    if not domain or not audience or not client_id:
        return
    application.swagger_ui_init_oauth = {
        "clientId": client_id,
        "usePkceWithAuthorizationCodeGrant": True,
        "scopes": " ".join(_SCOPES),
        # Asks for an access token for the API rather than for Auth0 itself.
        "additionalQueryStringParams": {"audience": audience},
    }
    default_openapi = application.openapi

    def openapi() -> dict[str, Any]:
        if application.openapi_schema is None:
            _add_login(default_openapi(), domain)
        return application.openapi_schema

    application.openapi = openapi
