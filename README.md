# Game Drawing Duel

Game Drawing Duel is a daily, sketch-based competitive game where players draw challenger portraits, assemble a party of legends, and decide who wins the matchup.

## Core loop

- Daily prompt and challenger assignment
- One quick drawing pass each cycle
- Party-building battle phase
- Vote-based resolution at the end of the round

## Design docs

- [docs/concept/premise.md](docs/concept/premise.md) — the main game loop and daily structure
- [docs/concept/features.md](docs/concept/features.md) — feature ideas and progression mechanics
- [docs/concept/initial-setup.md](docs/concept/initial-setup.md) — roster balance and timing assumptions
- [docs/concept/visuals.md](docs/concept/visuals.md) — visual style and presentation direction

## CI/CD

This is a mostly Azure-dependent app.
For bootstrapping, the following GitHub secrets are required:

- AZURE_CLIENT_ID
- AZURE_KEY_VAULT_NAME
- AZURE_SUBSCRIPTION_ID
- AZURE_TENANT_ID

### Pipelines

| Workflow | Runs on | What it does |
| --- | --- | --- |
| `validation.yml` | Every pull request | Runs only the checks for the parts a pull request touches. **Frontend:** `flutter analyze` and `flutter test`. **Backend:** `ruff check` and the unit tests. **Migrations:** applies all migrations to a fresh PostgreSQL, runs `alembic check` to make sure no migration is missing, then downgrades and upgrades again. Ends with the `Validation passed` check |
| `azure-swa-deployment.yml` | Pull requests and pushes to `main` touching `frontend/` | Builds the web app and deploys it to Azure Static Web Apps (pull requests get a preview environment with the gameplay mockup enabled) |
| `azure-functions-deployment.yml` | Pushes to `main` touching `backend/` | Runs the database migrations, stops if `alembic check` finds the models and the migrated schema out of sync, then deploys the Function App |

Pull requests can only be merged when `Validation passed` succeeds. It is a
required status check in the branch ruleset for `main`; skipped jobs count as
passing, so pull requests that only touch documentation can still be merged.

The deployment reads the database connection for the migrations from the Key
Vault secret `database-url`.

### API authentication

Every API route except `/health` and the API docs (`/docs`, `/redoc`,
`/openapi.json`) requires an Auth0 access token for the API configured in
`AUTH0_AUDIENCE` that carries the `read:api` permission. Players get it through
the `user` role; the Auth0 API needs **Enable RBAC** and **Add Permissions in the
Access Token** turned on so it appears in the token's `permissions` claim.
Tokens without it (e.g. machine-to-machine) get `403`. A player's first `PUT /me` creates their database record
linked to the Auth0 user id; game routes load that record for every request and
answer `403` until the signup is finished. `/health` also checks that the
database answers.

### Servers

A player creates a server with the full list of players (5 to 10, including
the admin) and gets a unique 6-digit code to share. Friends look the server up
with the code and claim the seat with their name; the lobby shows who joined.
Once everyone joined, the admin starts the initial drawing setup for everyone
(the server's `phase` goes from `lobby` to `setup`) and every player gets
their drawing assignments.

| Endpoint | Purpose |
| --- | --- |
| `POST /servers` | Create a server; you take the first seat as admin |
| `GET /servers/mine` | The servers you joined, newest first |
| `GET /servers/{code}` | Roster and who joined |
| `POST /servers/{code}/seats/{position}/claim` | Join by claiming a free seat (`409` if it is taken) |
| `POST /servers/{code}/setup` | Start the initial drawing setup; admin only |
| `GET /servers/{code}/assignments` | Your drawings for the setup: prompt, subject seat, the drawing it builds on and what you drew so far |
| `PUT /servers/{code}/assignments/{id}/drawing` | Draw or redraw an assignment: a title and the sketch's strokes |
| `GET /characters/{id}/sketch` | The strokes of a drawn character, for the players of its server |

### Drawings

Every drawing gets a new UUID: a `character` row in the database and a file of
that name in the storage container with the strokes as JSON (normalised
points, colours and brush widths, so the stroke effects can follow them).
The file's metadata labels it with the kind of drawing, server code, prompt,
rarity and the artist's and subject's seats. Redrawing creates a new
character and deletes the old file. The API reaches the container through
`app/storage.py`'s `FileStore` interface; in Azure that is the blob container
accessed with the Function App's managed identity, in tests an in-memory store.

#### Test sessions

Ticking **Test session** when creating a server (`"is_test": true`) makes a
server for trying the game with the real database and storage, at speed:

- It can start without everyone: only the players who joined take part.
- The initial setup is short: every active player draws three characters,
  *Basic*, *Knight* and *Legend*, of the other active players (or of
  themselves when playing alone).
- Days don't wait for real time. The admin can advance to the next day, and
  the day advances automatically once every active player has ended theirs.
  Players see who has ended their day when they refresh, not by polling.
- The lobby and the game show a TEST SESSION badge.

Players who join a test session after its setup started draw along, of the
players who joined until then. So far the flag, the badge and the short setup
exist; the day controls arrive with the daily loop.

### Game rules

The rules the server enforces (`backend/app/rules.py`) and the ones the app
plays by (`frontend/lib/game/rules`) are implemented on both sides.
[`shared/rules.json`](shared/rules.json) is the specification both are tested
against: player limits, rarities, the setup prompts per player count and who
draws whom. Change it together with both implementations.

### Function App settings

The app settings are managed in the infrastructure repository. The API reads:

| Setting | Value |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection string (same as the Key Vault secret `database-url`) |
| `FRONTEND_URL` | Origin of the web app, allowed for CORS |
| `AUTH0_DOMAIN` | Auth0 tenant domain without scheme, e.g. `your-tenant.eu.auth0.com` (same as `auth0-domain`) |
| `AUTH0_AUDIENCE` | Identifier of the Auth0 API (same as `auth0-api-audience`) |
| `STORAGE_ACCOUNT_NAME` | Storage account holding the drawings |
| `STORAGE_CONTAINER_NAME` | Blob container for the drawings |
| `FUNCTION_APP_CLIENT_ID` | Client id of the Function App's user-assigned managed identity, which needs **Storage Blob Data Contributor** on the container |

Without the two Auth0 settings every route except `/health` and the docs
answers `503 Authentication is not configured`.

### Planned: test infrastructure for pull requests

Once a test Function App and test database exist, pull requests should deploy
to them instead of only validating:

- `azure-functions-deployment.yml` also runs on pull requests touching
  `backend/`. A separate job migrates the test database and deploys to the test
  Function App, using the Key Vault secrets `function-app-name-test` and
  `database-url-test`. Like production, it runs one deployment at a time.
- `azure-swa-deployment.yml` builds pull request previews against the test API
  (Key Vault secret `api-custom-domain-test`) instead of the production one.

### Running the checks locally

```sh
# frontend
cd frontend && flutter analyze && flutter test

# backend
cd backend && uv sync --locked && uv run ruff check && uv run python -m unittest discover -s tests

# migrations (needs a PostgreSQL in DATABASE_URL)
cd backend && uv run alembic upgrade head && uv run alembic check
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
