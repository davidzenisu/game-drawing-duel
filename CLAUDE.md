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
- A request that belongs to an existing issue goes into that issue instead
  of a new one.

### Issue flow

Issues move through the status of the project board: Ready, In Progress,
then closed.

1. **Check the issue.** Read it, ask the user its open questions, and write
   the answers into the issue. Once none is left, set its status to
   **Ready**. If the user says to start on it right away, go straight to
   step 2.
2. **Start once the user says so.** Set its status to **In Progress**, then
   work on it on its own branch.
3. **Open a pull request when done, always**, without being asked. It
   references its issue with "Part of #N", never a keyword that closes the
   issue on merge ("Closes", "Fixes", "Resolves").
4. **Watch the CI** of the pull request until it's green, fixing what
   fails, then send the user the link to its Azure Static Web Apps preview
   environment (the deployment comment on the pull request).
5. **Close the issue only when the user says so** in the chat.
