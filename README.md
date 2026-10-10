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
their drawing assignments. Once a player drew all of theirs, they finish their
setup (no more redrawing); when the last one finishes, the game launches
(`phase` becomes `running`): all drawings form the pool and everyone's own
drawings start their collection.

Any player who joined can cancel the server at any point of the game, e.g. when
dropping out (the app asks twice, the second time after a 10-second
countdown). All its game data is deleted: drawings (also from storage),
pulls, upgrades, prompts, fights, votes and hurries. The server and its seats
stay, with `phase` `cancelled` and `cancelled_by` naming who cancelled, so the
other players find out when they return: any other request for the server
answers `410 Gone`, and the app shows who cancelled it, dismisses it and goes
back to creating or joining a server.

| Endpoint | Purpose |
| --- | --- |
| `POST /servers` | Create a server; you take the first seat as admin |
| `GET /servers/mine` | The servers you joined, newest first, including cancelled ones you haven't dismissed |
| `GET /servers/{code}` | Roster and who joined |
| `POST /servers/{code}/seats/{position}/claim` | Join by claiming a free seat (`409` if it is taken) |
| `DELETE /servers/{code}` | Cancel the server for everyone and delete all its game data; any player who joined |
| `POST /servers/{code}/dismiss` | You saw that the server was cancelled; it leaves `GET /servers/mine` |
| `POST /servers/{code}/setup` | Start the initial drawing setup; admin only |
| `GET /servers/{code}/assignments` | Your drawings for the setup: prompt, subject seat, the drawing it builds on and what you drew so far |
| `PUT /servers/{code}/assignments/{id}/drawing` | Draw or redraw an assignment: a title and the sketch's strokes |
| `POST /servers/{code}/setup/done` | Finish your setup drawings; the last player to finish launches the game |
| `GET /servers/{code}/pool` | Every character of a launched game |
| `GET /servers/{code}/collection` | Your characters (your setup drawings and pulls) with how many copies you own |
| `GET /servers/{code}/gacha` | Your pulls left and pity progress |
| `POST /servers/{code}/pulls` | Spend 1 to 10 pulls on random characters of the pool |
| `POST /servers/{code}/collection/{id}/upgrades` | Spend a duplicate on the character's next upgrade (`{"element": …}` for the element upgrade) |

### Daily loop

Day 1 is the launch day; regular servers move to the next day at midnight
UTC, and each day has a theme. Every day each player:

1. writes a challenger title for the day's theme and a randomly picked
   character (not themselves and not the player who draws it),
2. draws the title the previous player wrote the day before; if they wrote
   none, a premade title (`app/premade_prompts.py`) stands in. The challenger
   joins the pool as a hero and earns the day's only pull
   (`challenger:day-N`).
3. sends up to four characters of their collection against a random
   challenger drawn the day before (not their own),
4. votes on the day before's fights, except their own and those against
   their challenger: do the fighters beat the challenger?

A fight is decided once its voting day is over, i.e. two days after the
fighters were picked; ties go to the challenger. Whatever a player leaves
out is decided by chance: a player who picked no fighters gets random ones
from their collection (stored the first time the next day is opened), and a
missing vote is random, weighted by the team's strength
(`rules.fighter_odds`, shared with the mockup).

The random picks are derived from the server, day and seat (or fight), so
they stay the same without being stored ahead of time.

Every day each player can also send one free hurry to another player: it
takes 30 seconds off their challenger drawing at a random moment between a
quarter and 60% of the time limit, which they only find out while drawing.

| Endpoint | Purpose |
| --- | --- |
| `GET /servers/{code}/today` | Day, theme, your prompt to write and to draw, your fight, the fights to vote on and your decided fights |
| `POST /servers/{code}/today/prompt` | Write today's challenger title, once |
| `PUT /servers/{code}/today/challenger` | Draw today's challenger, once |
| `PUT /servers/{code}/today/fighters` | Send up to four fighters against today's challenger, once |
| `POST /servers/{code}/today/votes/{fight}` | Vote on one of yesterday's fights, once |
| `POST /servers/{code}/today/hurry` | Send today's free hurry to another player, once |
| `POST /servers/{code}/today/end` | Test sessions: end your day; the next starts once everyone did |
| `POST /servers/{code}/days/next` | Test sessions: the admin starts the next day |

### Gacha

Every pull a player earns is a `pull_grant` row with a timestamp and the
reason it was awarded, e.g. `launch-bonus:3` (everyone gets 10 at the
launch). A seat can't receive the same reason twice. A `pull` spends exactly
one grant (`grant_id` is unique) on a character, numbered per seat; a
player's pulls are serialised with a row lock, so the same grant can't be
spent twice. The rarity is rolled on the server (`app/gacha.py`) with the
rates and pity from `docs/concept/gacha-rates.md`: the pity follows from a
player's pulls so far instead of being stored. Duplicates are copies of a
character in the collection: each one unlocks the next upgrade of the
character's rarity path (`upgrade` rows, one per effect). Only the mockup
unlocks upgrades on credit.
| `GET /characters/{id}/sketch` | The strokes of a drawn character, for the players of its server |

### Database ids

Every table's primary key is a UUID the API generates (`uuid4`), so ids in the
API reveal nothing about how many players, servers or drawings exist. What
players see and type are the 6-digit server codes and seat positions.

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
  *Basic*, *Knight* and *Legend*, of three different, randomly picked other
  players of the whole roster, whether they joined or not.
- Days don't wait for real time. The admin can advance to the next day, and
  the day advances automatically once every active player has ended theirs.
  Players see who has ended their day when they refresh, not by polling.
- The lobby and the game show a TEST SESSION badge.

Players who join a test session after its setup started draw along, and the
launch waits for them too; once it launched, nobody can join anymore. The day
controls are in the daily hub: everyone can end their day, the admin can start
the next one, and a refresh shows who ended theirs.

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
