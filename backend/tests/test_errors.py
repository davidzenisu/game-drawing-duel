import os
import unittest
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.engine import make_url
from sqlalchemy.exc import TimeoutError as SQLAlchemyTimeoutError

from app.database import engine_options
from app.main import configure_error_handling, configure_frontend_cors

FRONTEND = "https://drawing.example"


def _app() -> FastAPI:
    """An app set up like the API, with routes that fail."""
    application = FastAPI()
    configure_error_handling(application)
    with patch.dict(os.environ, {"FRONTEND_URL": FRONTEND}):
        configure_frontend_cors(application)

    @application.get("/boom")
    def boom() -> None:
        raise RuntimeError("a bug")

    @application.get("/busy")
    def busy() -> None:
        raise SQLAlchemyTimeoutError("QueuePool limit of size 10 overflow 20 reached")

    return application


class ErrorHandlingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(_app(), raise_server_exceptions=False)

    def test_an_unhandled_error_is_logged_and_readable_by_the_browser(self) -> None:
        with self.assertLogs("app", "ERROR") as logs:
            response = self.client.get("/boom", headers={"Origin": FRONTEND})
        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json(), {"detail": "Something went wrong on the server"})
        self.assertEqual(response.headers["access-control-allow-origin"], FRONTEND)
        self.assertIn("Unhandled error in GET /boom", logs.output[0])
        self.assertIn("RuntimeError: a bug", logs.output[0], "with its traceback")

    def test_a_busy_database_is_a_503_worth_trying_again(self) -> None:
        with self.assertLogs("app", "ERROR") as logs:
            response = self.client.get("/busy", headers={"Origin": FRONTEND})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.headers["access-control-allow-origin"], FRONTEND)
        self.assertIn("Database unavailable for GET /busy", logs.output[0])


class EngineOptionTests(unittest.TestCase):
    def test_postgres_goes_through_the_transaction_pooler(self) -> None:
        options = engine_options(make_url("postgresql+psycopg://u:p@pooler:6543/db"))
        self.assertEqual(options["connect_args"], {"prepare_threshold": None}, "no prepared statements")
        self.assertEqual((options["pool_size"], options["max_overflow"]), (10, 20))
        self.assertEqual(options["pool_timeout"], 10)

    def test_the_pool_can_be_tuned(self) -> None:
        with patch.dict(os.environ, {"DATABASE_POOL_SIZE": "4", "DATABASE_POOL_TIMEOUT": "2.5"}):
            options = engine_options(make_url("postgresql+psycopg://u:p@pooler:6543/db"))
        self.assertEqual((options["pool_size"], options["pool_timeout"]), (4, 2.5))

    def test_sqlite_keeps_its_own_pool(self) -> None:
        self.assertEqual(engine_options(make_url("sqlite://")), {"pool_pre_ping": True})
