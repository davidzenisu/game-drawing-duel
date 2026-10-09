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
`AUTH0_AUDIENCE`. A player's first `PUT /me` creates their database record
linked to the Auth0 user id; game routes load that record for every request and
answer `403` until the signup is finished. `/health` also checks that the
database answers.

### Function App settings

The app settings are managed in the infrastructure repository. The API reads:

| Setting | Value |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection string (same as the Key Vault secret `database-url`) |
| `FRONTEND_URL` | Origin of the web app, allowed for CORS |
| `AUTH0_DOMAIN` | Auth0 tenant domain without scheme, e.g. `your-tenant.eu.auth0.com` (same as `auth0-domain`) |
| `AUTH0_AUDIENCE` | Identifier of the Auth0 API (same as `auth0-api-audience`) |

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
