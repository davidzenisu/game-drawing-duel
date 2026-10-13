"""Which commit is running, so a deployment can check it went live.

The deployment writes the commit hash into `BUILD_SHA` next to the app
before uploading it; local runs and tests have no such file.
"""

from pathlib import Path

BUILD_FILE = Path(__file__).resolve().parent.parent / "BUILD_SHA"


def version() -> str:
    """The deployed commit hash, or "dev" when not deployed."""
    try:
        return BUILD_FILE.read_text().strip() or "dev"
    except OSError:
        return "dev"
