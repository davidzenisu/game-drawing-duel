import importlib
import logging
import os
import sys

import azure.functions as func

if os.environ.get("WEBSITE_RUN_FROM_PACKAGE") == "1":
    package_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "packages"))
    sys.path.append(package_path)

fastapi_app = importlib.import_module("app.main").app

logging.getLogger("azure").setLevel(logging.ERROR)

app = func.AsgiFunctionApp(
    app=fastapi_app,
    http_auth_level=func.AuthLevel.ANONYMOUS,
)