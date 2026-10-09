# frontend

## Auth0

The web app reads `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, `AUTH0_AUDIENCE` and
`API_URL` at build time from `config/config.json` using Flutter's
`--dart-define-from-file` option. Start local development by creating the
ignored config file from the example:

```sh
cp config/config.json.example config/config.json
```

Replace the example values with your Auth0 domain, client ID and the identifier
of the Auth0 API (the audience the backend accepts), then run the VS Code
**Flutter: Frontend (Codespaces)** launch configuration or start Flutter with
`flutter run -d chrome --web-port 7357 --dart-define-from-file=config/config.json`.
`API_URL` is the API base URL; the example uses the local Functions host at
`http://localhost:7071`.

Signing in redirects to Auth0. Back in the app, `GET /me` decides whether the
player still has to finish the signup (pick a first name, prefilled from the
social login) or is ready to play. Every API call carries the Auth0 access
token for `AUTH0_AUDIENCE`.

Register `http://localhost:7357` in the Auth0 application's **Allowed Callback
URLs**, **Allowed Logout URLs**, and **Allowed Web Origins**. Add the production
origin to the same settings.

The Azure Static Web Apps workflow reads these values from Key Vault
(`auth0-domain`, `auth0-client-id`, `auth0-api-audience`, `api-custom-domain`),
writes a temporary JSON defines file, and passes it to the release build. These
values are included in the client-side app, so they are not secrets.

## Mockup gameplay loop

The app can run an offline mockup of the gameplay loop described in
`docs/concept`: account creation, server creation/join, the initial drawing
setup, gacha pulls with duplicate upgrades, and the daily loop. Every challenger
goes through four days, and each day every player works on a different stage:

1. write a challenger title prompt for the day's theme and a given character,
2. draw a challenger from a prompt another player wrote the day before,
3. pick up to four fighters against a challenger drawn the day before,
4. vote who would win the fights the others set up the day before.

Afterwards the fights play out under **Battle results** for the players who drew
the challenger or picked the fighters. Everything happens in memory within a
single session; the other players are simulated and no backend, database or
Auth0 is used.

Enable it with the `MOCKUP_GAMEPLAY` feature flag, either in
`config/config.json` (`"MOCKUP_GAMEPLAY": true`) or directly:

```sh
flutter run -d chrome --dart-define=MOCKUP_GAMEPLAY=true
```

The flag defaults to `false`, so regular builds are unaffected.

### Code layout

- `lib/game/`: everything the game needs regardless of where it is played.
  - `rules/`: the game rules (setup plan, gacha rates and pity, upgrade paths,
    daily loop, themes).
  - `screens/` and `widgets/`: the UI.
  - `game_session.dart`: the `GameSession` interface the screens use. State is
    read synchronously; actions return futures so a backend can implement it.
- `lib/mockup/`: `MockGameSession`, the in-memory implementation behind the
  mockup, with simulated players.
- `lib/backend/`: `ApiGameSession`, the implementation backed by the API and
  Auth0. Signing in and signing up work; the rest of the game follows step by
  step and reports that it isn't available yet.
- `lib/theme/palette.dart`: the shared colour palette.
