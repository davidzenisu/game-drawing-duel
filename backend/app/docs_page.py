"""The interactive API docs (`/docs`) with the game's logo as their icon.

FastAPI's own docs page takes no icon, so the app turns it off
(`docs_url=None`) and this module serves the same page with the logo, along
with the login redirect page the default docs come with, and the logo itself
at `/favicon.png`.
"""

from pathlib import Path

from fastapi import FastAPI
from fastapi.openapi.docs import (
    get_swagger_ui_html,
    get_swagger_ui_oauth2_redirect_html,
)
from fastapi.responses import FileResponse, HTMLResponse

LOGO = Path(__file__).resolve().parent / "static" / "logo.png"
DOCS_URL = "/docs"
LOGO_URL = "/favicon.png"


def configure_docs_page(application: FastAPI) -> None:
    """Serves the docs at `DOCS_URL`, for an app created with `docs_url=None`."""
    redirect_url = application.swagger_ui_oauth2_redirect_url

    def docs() -> HTMLResponse:
        # Read on each request: `configure_docs_login` sets the login later.
        return get_swagger_ui_html(
            openapi_url=application.openapi_url,
            title=f"{application.title} - Swagger UI",
            oauth2_redirect_url=redirect_url,
            init_oauth=application.swagger_ui_init_oauth,
            swagger_favicon_url=LOGO_URL,
            swagger_ui_parameters=application.swagger_ui_parameters,
        )

    application.add_api_route(DOCS_URL, docs, methods=["GET"], include_in_schema=False)
    if redirect_url:
        application.add_api_route(
            redirect_url,
            get_swagger_ui_oauth2_redirect_html,
            methods=["GET"],
            include_in_schema=False,
        )

    def logo() -> FileResponse:
        return FileResponse(LOGO, media_type="image/png")

    application.add_api_route(LOGO_URL, logo, methods=["GET"], include_in_schema=False)
