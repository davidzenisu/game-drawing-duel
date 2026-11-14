import re
import tomllib
import unittest
from pathlib import Path

from app.main import app

ROOT = Path(__file__).resolve().parents[2]


class VersionTests(unittest.TestCase):
    def test_the_api_has_the_version_of_the_latest_release_notes(self) -> None:
        notes = (ROOT / "CHANGELOG.md").read_text()
        latest = re.search(r"^## \[(\d+\.\d+\.\d+)\] - \d{4}-\d{2}-\d{2}$", notes, re.MULTILINE)
        self.assertIsNotNone(latest, "the release notes have a version")
        pyproject = tomllib.loads((ROOT / "backend" / "pyproject.toml").read_text())
        self.assertEqual(pyproject["project"]["version"], latest.group(1))
        self.assertEqual(app.version, latest.group(1))
