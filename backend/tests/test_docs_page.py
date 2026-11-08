import os
import unittest
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.docs_login import configure_docs_login
from app.docs_page import LOGO, configure_docs_page
from app.main import app
from tests.test_docs_login import SETTINGS


class DocsPageTests(unittest.TestCase):
    def test_the_docs_show_the_logo(self) -> None:
        client = TestClient(app)
        docs = client.get("/docs")
        self.assertEqual(docs.status_code, 200)
        self.assertIn('href="/favicon.png"', docs.text)
        self.assertIn("Game Drawing Duel API - Swagger UI", docs.text)
        logo = client.get("/favicon.png")
        self.assertEqual(logo.status_code, 200)
        self.assertEqual(logo.headers["content-type"], "image/png")
        self.assertEqual(logo.content, LOGO.read_bytes())
        # Neither is part of the API.
        paths = client.get("/openapi.json").json()["paths"]
        self.assertNotIn("/docs", paths)
        self.assertNotIn("/favicon.png", paths)

    def test_the_docs_still_sign_in_with_auth0(self) -> None:
        application = FastAPI(docs_url=None)
        configure_docs_page(application)
        with patch.dict(os.environ, SETTINGS, clear=True):
            configure_docs_login(application)
        client = TestClient(application)
        docs = client.get("/docs").text
        self.assertIn('"clientId": "docs-client"', docs)
        self.assertIn('href="/favicon.png"', docs)
        self.assertEqual(client.get("/docs/oauth2-redirect").status_code, 200)
        posted = client.post(
            "/docs/oauth2-redirect", data={"code": "abc"}, follow_redirects=False
        )
        self.assertEqual(posted.status_code, 303)
