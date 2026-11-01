# Game Drawing Duel

Game Drawing Duel is a daily, sketch-based competitive game where players draw challenger portraits, assemble a party of legends, and decide who wins the matchup.

## Core loop

- Daily prompt and challenger assignment
- One quick drawing pass each cycle
- Party-building battle phase
- Boosts for the challengers, and the stars decide the fights
- A weekly finale: the week's challengers are ranked by their stars; the best joins the gacha pool as a hero

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
database answers, and reports the commit that's running as `version` (`dev`
outside a deployment). The backend deployment writes it into the package and
fails unless the live API reports it within 10 minutes.

`GET /me` lists the tutorials the player saw (`tutorials_seen`), and
`PUT /me/tutorials/{key}` marks one as seen, so the app shows each only once,
on any device. Keys are short lowercase names the app picks (`[a-z0-9-]`, up
to 40 characters); seeing one again changes nothing.

#### Signing in to the API docs

With `AUTH0_DOCS_CLIENT_ID` set, the interactive docs at `/docs` sign in with
Auth0 instead of needing a pasted token: **Authorize** → **Auth0** (leave
`client_secret` empty) → **Authorize** runs the same login as the game
(authorization code flow with PKCE, for `AUTH0_AUDIENCE`) and sends the access
token with every **Try it out**. Use an account that finished signing up in the
game. Pasting a token under **HTTPBearer** keeps working.
Auth0 posts the login code back (`response_mode=form_post`) and the API
redirects to the same page with the code in the URL fragment: Azure Functions
reads a `code` query parameter as a function key and would fail the redirect
with a `500`.

The setting is the client id of an Auth0 **Single Page Application**. The game's
own application works, or create a separate one (e.g. "API docs") so its
callback can be removed or the docs login switched off without touching the
game's. Either way, in its settings:

- **Allowed Callback URLs**: add `<API URL>/docs/oauth2-redirect`, e.g.
  `https://<function-app>.azurewebsites.net/docs/oauth2-redirect`. Auth0 also
  allows that origin for the token request (CORS).
- A separate application needs the same login connections as the game
  (**Connections** tab), and access to the API: allow it under the API's
  **Application Access** if the tenant requires authorizing user access.

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
pulls, upgrades, prompts, fights, boosts and hurries. The server and its seats
stay, with `phase` `cancelled` and `cancelled_by` naming who cancelled, so the
other players find out when they return: any other request for the server
answers `410 Gone`, and the app shows who cancelled it, dismisses it and goes
back to creating or joining a server.

| Endpoint | Purpose |
| --- | --- |
| `POST /servers` | Create a server (`"mode": "regular"` or `"speed"`); you take the first seat as admin |
| `GET /servers/mine` | The servers you joined, newest first, including cancelled ones you haven't dismissed |
| `GET /servers/{code}` | Roster and who joined |
| `POST /servers/{code}/seats/{position}/claim` | Join by claiming a free seat (`409` if it is taken) |
| `DELETE /servers/{code}` | Cancel the server for everyone and delete all its game data; any player who joined |
| `POST /servers/{code}/dismiss` | You saw that the server was cancelled; it leaves `GET /servers/mine` |
| `POST /servers/{code}/setup` | Start the initial drawing setup; admin only |
| `GET /servers/{code}/assignments` | Your drawings for the setup: prompt, subject seat, starter prompt (`hint`), the drawing it builds on and what you drew so far |
| `PUT /servers/{code}/assignments/{id}/drawing` | Draw or redraw an assignment: a title and the sketch's strokes |
| `POST /servers/{code}/setup/done` | Finish your setup drawings; the last player to finish launches the game |
| `GET /servers/{code}/pool` | The gacha pool of a launched game: everyone's setup drawings |
| `GET /servers/{code}/collection` | Your characters (your setup drawings and pulls) with how many copies you own |
| `GET /servers/{code}/gacha` | Your pulls left and pity progress |
| `POST /servers/{code}/pulls` | Spend 1 to 10 pulls on random characters of a banner (`{"banner": "standard"}` by default, or `"weekly"` from the first finale on) |
| `POST /servers/{code}/collection/{id}/upgrades` | Spend a duplicate on the character's next upgrade (`{"element": …}` for the element upgrade) |

### Daily loop

Day 1 is the launch day; regular servers move to the next day at midnight
UTC, and each day has the theme of its weekday (see "Themes" below). Every
day each player:

1. gets a description (one of the prompt hints), chooses the person who fits
   it best (anyone but themselves; several players may choose the same one)
   and writes a challenger title for them. The challenger takes the theme of
   the day it's fought, three days later, so each day's theme is the one of
   the challengers fought on it,
2. draws, within 1:30, the title the previous player wrote the day before,
   seeing the description it was written for too; if they wrote none, the
   premade title of their description stands in (with the description), for
   a random person other than them.
   The challenger
   is a hero and earns a pull (`challenger:day-N`). It doesn't
   join the gacha pool unless it wins a weekly finale (see below).
3. spreads 3 boost stars across up to three of the challengers drawn the day
   before, at most 3 on one, never the one they drew or the one they fight
   tomorrow. Everyone boosts the challengers of the players the same
   offsets on in the roster (picked per day), so when everyone drew, every
   challenger is boosted by three players and comes first for one of them;
   later offsets stand in for players who drew none. The stars can change
   all day; once it's over, chance spreads the ones a player left
   (`boost.by_chance`).
4. sends up to four characters of their collection against a challenger
   drawn two days before: the one of the player a number of seats on in the
   roster (picked per day; the next one on who drew stands in for a player
   who drew none). So when everyone drew, every challenger has exactly one
   fight and nobody fights their own. Every character fights
   once a week: after a fight it rests until Monday (UTC, the week of the
   themes), and `GET today` lists the resting ones as `fight.resting`.
   Basic (1-star) characters can fight every day, and everyone draws one
   during the setup, so nobody runs out. Fighters picked by chance come from
   the characters that can fight that day.

A fight is decided as soon as the fighters are picked, by stars: the
fighters' rarities (1 for a basic up to 4 for a legend; upgrades don't count
yet) against the challenger's 3 plus its boost stars, which stay secret
until then. The fighters need more stars to win; ties go to the challenger
(`rules.fighters_win`, shared with the mockup). With teams of four rolled at
the gacha rates and boosts spread at random, the fighters win a bit over
half the fights (`tests/test_balance.py`). A win earns a pull
(`fight:day-N`) and the challenger's stars as **victory stars**, a currency
to spend later (`victory_stars` in `GET gacha`, summed from the won fights).
A player who picked no fighters gets random ones from their collection once
the day is over (stored the first time the next day is opened); their wins
earn nothing. The next day, `GET today` lists those fights and the ones
against the player's challenger as `results`; the app doesn't show them for
now.

A fight's result is stored on its `fight` row (`boosts`, the challenger's
boost stars, `fighter_stars`, `challenger_stars`, `fighters_win`), so later
rule changes don't rewrite past fights. For example, how each player's
characters fared against each player's challengers, counting every fighter
of a team, without teams chance picked:

```sql
SELECT fighter.name AS fighter, challenger.name AS challenger,
       count(*) FILTER (WHERE f.fighters_win) AS wins,
       count(*) FILTER (WHERE NOT f.fighters_win) AS losses
FROM game.fight f
JOIN game.fighter fr ON fr.fight_id = f.id
JOIN game.character fc ON fc.id = fr.character_id
JOIN game.server_seat fighter ON fighter.id = fc.subject_seat_id
JOIN game.character cc ON cc.id = f.challenger_id
JOIN game.server_seat challenger ON challenger.id = cc.subject_seat_id
WHERE f.fighters_win IS NOT NULL AND NOT f.by_chance
GROUP BY fighter.name, challenger.name
ORDER BY fighter.name, challenger.name;
```

Seat names are per server; to follow a player across servers, group by
`server_seat.player_id` instead.

Once a week is over (after Sunday, UTC) comes the finale: the week's
challengers are ranked by their stars, their own 3 plus their boost stars.
A challenger counts for the week of its boosting day, the day after it was
drawn, so its stars are final when the week ends (a challenger drawn on a
Sunday counts for the next week). Every challenger is ranked; the one with
the most stars (then the most fights won by the end of the week, then the
one drawn first) joins the gacha pool as a hero (`app/finale.py`). `GET
today` shows the latest winner as `weekly_hero`, and `GET ranking` the whole
ranking of the latest finished week.

The random picks are derived from the server, day and seat, so they stay the
same without being stored ahead of time.

Every day each player can also send one free hurry to another player: at a
random moment between a quarter and 60% of the time limit, it takes 10% of
the time left off their challenger drawing, which they only find out while
drawing. Every hurry a player receives counts, each on the time left when it
hits (`GET today` lists them as `incoming_hurries`).

| Endpoint | Purpose |
| --- | --- |
| `GET /servers/{code}/today` | Day, theme, your prompt to write and to draw, the challengers to boost with the stars you gave them, your fight, yesterday's results and the latest weekly hero |
| `POST /servers/{code}/today/prompt` | Choose a person for today's description (`subject_position`, anyone but you) and write their challenger title, once |
| `PUT /servers/{code}/today/challenger` | Draw today's challenger, once |
| `PUT /servers/{code}/today/boosts` | Spread your boost stars across today's challengers to boost (`boosts`, each a `challenger_id` and its `stars`), replacing the ones you gave today |
| `PUT /servers/{code}/today/fighters` | Send up to four fighters against today's challenger, once; the stars decide right away |
| `POST /servers/{code}/today/hurry` | Send today's free hurry to another player, once |
| `GET /servers/{code}/ranking` | The latest finished week's challengers, most stars first, with their stars, fights and wins; `null` before the first week is over. In speed mode, all of the session's challengers once it's over |
| `GET /servers/{code}/challengers` | The challengers you encountered (drew, fought against or boosted), newest first, with their decided fights and wins |
| `POST /servers/{code}/today/end` | Speed mode and test sessions: end your day; the next starts once everyone did |
| `POST /servers/{code}/days/next` | Speed mode and test sessions: the admin starts the next day |

### Themes

Every weekday has a fantasy theme, by the calendar in UTC: Monday the
Enchanted Forest, then Hot Sandy Beaches, Volcano Lair, Frozen Peaks, Misty
Jungle, Outer Space and the Royal Castle on Sunday. Test sessions count the
calendar on from their launch date as their days advance. The app shows only
the fantasy name; everyday situations that fit it come with the **prompt
hints** (`theme_hint`): each a description a player chooses a person and
writes a title for, and the premade title that stands in if they write none.
The first ones are in `docs/concept/themes.md`.

It's a database table, so new ones can be added any time. Accounts with the
`edit:content` permission (see below) manage them in the app or through the
API, e.g. in `/docs`; the Supabase table editor or SQL work too:

```sql
insert into theme_hint (theme, text, premade_title)
values ('volcano', 'a challenger who microwaves fish at work', 'Lord of the Office Microwave');
```

`theme` is one of `forest`, `beach`, `volcano`, `snow`, `jungle`, `space` and
`castle`; titles are at most 60 characters. A new row counts from the day
after it was added, and a retired one (`retired_at`) until the end of the day
it was retired, so the picks of a day never change. A server uses every hint
once only, ever: when a day's hints are first asked for, every player gets a
different one the server never gave out (`hint_assignment`), in an order of
the server's own. Once a theme's hints are used up, players get none and the
app shows "NO PROMPT" (they still choose a person and write a title), so a
theme needs about as many new hints a week as the server has players. A
player without a hint who writes no title has the fallback title "The Mystery
Challenger" drawn.

The setup drawings come with **starter prompts** (`setup_hint`) too: what a
drawing should show of the person drawn, e.g. "Them by night" for the alter.
Each setup prompt type (`basic`, `alter`, `knight`, `mage`, `rogue`, `hero`,
`legend`) starts with six. When the setup starts, every drawing gets a random
one of its type that isn't retired (`setup_assignment.hint_id`), without
repeats within the server until the type's run out. New rows are picked from
the next setup on:

```sql
insert into setup_hint (prompt, text) values ('rogue', 'The last thing they lied about');
```

| Endpoint | Purpose |
| --- | --- |
| `GET /content/hints?theme=` | The prompt hints in use, optionally of one theme |
| `POST /content/hints` | Add hints to a theme: `theme` and `hints`, each a `text` and its `premade_title`; descriptions the theme has already (ignoring case) are skipped |
| `DELETE /content/hints/{id}` | Retire a hint: it's still used for the rest of the day |
| `GET /content/setup-hints?prompt=` | The starter prompts in use, optionally of one setup prompt type |
| `POST /content/setup-hints` | Add starter prompts to a type: `prompt` and `texts`; texts the type has already (ignoring case) are skipped |
| `DELETE /content/setup-hints/{id}` | Retire a starter prompt: setups started from then on don't get it |

The content endpoints need the `edit:content` permission of the Auth0 API on
top of the player permission (`read:api`). `GET /me` tells the app with
`can_edit_content`: content editors get a "Game content" button in the app
bar to list, add and retire prompts per theme, each a description with its
premade title, and the starter prompts per setup prompt type. Give it through a role, like the
`user` role gives `read:api`; the Auth0 setup lives in the infrastructure
repository.

### Gacha

Every pull a player earns is a `pull_grant` row with a timestamp and the
reason it was awarded, e.g. `launch-bonus:3` (everyone gets 10 at the
launch). A seat can't receive the same reason twice. A `pull` spends exactly
one grant (`grant_id` is unique) on a character, numbered per seat; a
player's pulls are serialised with a row lock, so the same grant can't be
spent twice. Each pull is on a banner (`pull.banner`): the standard one is
always there and has the setup drawings, with a legend guaranteed once within
a player's first 10 standard pulls; the weekly one opens with the first
finale and has the whole pool, weekly heroes included. The rarity is rolled
on the server (`app/gacha.py`) with the rates and pity from
`docs/concept/gacha-rates.md`: the pity follows from a player's pulls so far
instead of being stored, and the legend pity counts both banners. Within the
rolled rarity, every character is equally likely except, on the weekly
banner, this week's rate-up: the latest
weekly hero and the pool's legends of the same player share 50% of their
rarity (all of it if they're alone in it), and change every Monday with the
finale (`app.pulls.rate_up`, sent as `rate_up` with `GET /servers/{code}/gacha`).
Duplicates are copies of a
character in the collection: they unlock the upgrades of the character's
rarity path in order (`upgrade` rows, one per effect), each step costing
at least as many duplicates as the one before (`UPGRADE_COSTS`: 1, 2, 3, 5,
7 and 10 for the six steps of a 1 star, about 30 to max out a 1 or 2 star). Only the mockup unlocks upgrades on credit.
| `GET /characters/{id}/sketch` | The strokes of a drawn character, for the players of its server |

### Database schema

The game's tables, and Alembic's `alembic_version`, live in their own
PostgreSQL schema, `game` (`SCHEMA` in `app/database.py`), not in `public`:
Supabase's Data API serves `public` to anyone with the project's anon key,
and none of the tables has row-level security. The API connects as the role
in `DATABASE_URL`; Supabase's `postgres` user owns the tables, any other role
needs `USAGE` on the schema and privileges on its tables. Migrations name
the schema explicitly, starting from a single baseline (`6df1c84a8f00`) with
every table as it was when the tables moved there, and the seeded theme
hints. Alembic's `env.py` creates the schema on a fresh database and only
compares that one. The SQLite unit tests map it to SQLite's main
database.

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

#### Speed mode

Choosing **Speed** when creating a server (`"mode": "speed"`) makes a one-off
session of about 17 minutes, for playing the whole loop in one sitting
(`app/speed.py`, timings in `shared/rules.json` under `speed`):

- Everyone joins, like a regular server (5 to 10 players). The setup lasts 5
  minutes: everyone draws the basic character of the next player and a rarer
  one (adventurer, hero or legend, spread per player count) of the player
  after. Each player keeps only their basic drawing; the rarer ones go into
  the pool. The setup launches once everyone is done, or when the time is up
  with the drawings made so far (`setup_ends_at` in the server response).
- Days 1 to 6 follow back to back on timers (1, 2, 3, 3, 2 and 1 minutes).
  Challenger prompts are written on days 1 to 3 only, so the last days
  finish the loop: drawing on days 2 to 4, boosting on 3 to 5, fighting on
  4 to 6. `GET today` says when the day ends (`ends_at`); `prompt` is null on
  days without prompts.
- A day ends early once every player did everything there is to do, or
  ended their day (`POST today/end`); the admin can also start the next day
  (`POST days/next`). After day 6 the session is over (phase `finished`):
  `GET ranking` then ranks all of the session's challengers by their stars,
  and the app presents the winner with its stars, then scrolls through
  every other challenger.
- A won fight earns a pull per star of the challenger (`fight:day-N:1`,
  …) instead of one, so the strongest challengers pay the most.
- There is no weekly finale.

#### Test sessions

Test sessions (`"is_test": true`) start without everyone, use a short setup
and let the day be advanced on demand. Speed mode replaced them for players:
only accounts with the `manage:servers` permission can create one, for
debugging and the automated tests, and the ones still running when they were
retired were closed for their players like a cancelled server (migration
`b17ad0eded77`).

`POST /manage/servers/cleanup` deletes every test session and speed mode
session created more than a day ago, with its seats, game data and drawings,
and returns the deleted codes. It needs the `manage:servers` permission of
the Auth0 API on top of the player permission; like `edit:content`, give it
through a role in the infrastructure repository.

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
| `AUTH0_DOCS_CLIENT_ID` | Optional: client id of the Auth0 application the API docs sign in with (see "Signing in to the API docs") |
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
