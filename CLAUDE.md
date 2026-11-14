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

- Every pull request that changes something players notice adds a line
  to it, in players' words, under Added, Changed, Removed or Fixed.
- One version per week (Monday to Sunday, UTC), following semantic
  versioning: the week's first change starts a new version (minor with a
  new feature, patch with fixes only; a patch becomes a minor once a
  feature joins it), dated with the day of its latest change.
- Keep the versions in `frontend/pubspec.yaml`, `backend/pyproject.toml`
  (and `backend/uv.lock`, via `uv lock`) and `backend/app/main.py` equal to
  the latest one; tests check it.
