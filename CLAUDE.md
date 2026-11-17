# Working on this repository

## Concept docs

The game's concept docs live in `docs/concept/` (published from an
Obsidian vault: keep each file's front matter as it is).

- Whenever a change affects something a concept doc describes (rules,
  numbers, screens, flows, speed mode, the mockup…), update the doc in
  the same pull request as the code change.
- Describe what's built, in the docs' own style; leave sections marked
  as concepts or open ideas alone unless the change settles them.

## Release notes

`CHANGELOG.md` at the root holds the release notes; the app bundles the
same file and shows it under **What's new** in the account menu.

- Until a release mechanism is set up, every pull request that changes
  something players notice is a version of its own: it adds a new version
  at the top, with its changes in players' words under Added, Changed,
  Removed or Fixed. Never add to an existing version.
- Versions follow semantic versioning: minor (0.11.0 → 0.12.0) when the
  pull request adds or changes something, patch (0.12.0 → 0.12.1) when it
  only fixes. Date it with the day it's opened (UTC), and update the date
  if it's merged on a later day.
- If another version lands on main first, take the next number above it
  when bringing main in.
- A pull request players don't notice (internal changes, tests, docs only)
  adds no version.
- Keep the versions in `frontend/pubspec.yaml`, `backend/pyproject.toml`
  (and `backend/uv.lock`, via `uv lock`) and `backend/app/main.py` equal to
  the latest one; tests check it.

## GitHub issues

Every change, bugfix or feature, is tracked by a GitHub issue.

- Before starting a change that has no issue yet, create one: what's wrong
  or wanted, how it works today (with the code it touches), a proposal, the
  open questions and the scope (backend, frontend, docs, release notes).
  Player reports keep their wording, translated to English if needed.
- Label every issue with the repository's existing labels, never new ones:
  one kind (`bug` or `enhancement`) and the parts it touches (`frontend`,
  `backend`, `database`, `storage`, `infra`, `ci-cd`, `testing`,
  `performance`, `security`, `privacy`, `observability`, `tech-debt`).
- Pull requests reference their issue: "Closes #N" when they finish it,
  "Part of #N" when more is left. A request that belongs to an existing
  issue goes into that issue instead of a new one.
