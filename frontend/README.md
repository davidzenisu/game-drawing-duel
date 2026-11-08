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
token for `AUTH0_AUDIENCE`. Signing out (app bar, or "Use a different account"
on the signup) logs out of Auth0 and returns to the app.

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

1. choose a player for the day's description and write their challenger title,
2. draw a challenger from a prompt another player wrote the day before,
3. spread boost stars across a few of the challengers drawn the day before,
4. pick up to four fighters against a challenger drawn two days before.

Everything happens in memory within a single session, and no backend, database
or Auth0 is used. The other players are sample data on canned demo days, not a
simulation. "Start on day 8" on the sign-up screen jumps straight to the Monday
after a first week, with its ranking, weekly hero and win rates.

Every pull request that changes the frontend gets a preview site running the
mockup, so UI changes can be tried and screenshotted before they are merged.

Enable it with the `MOCKUP_GAMEPLAY` feature flag, either in
`config/config.json` (`"MOCKUP_GAMEPLAY": true`) or directly:

```sh
flutter run -d chrome --dart-define=MOCKUP_GAMEPLAY=true
```

The flag defaults to `false`, so regular builds start the real app.

In the real app, players with the `manage:servers` permission (`GET /me`
reports `can_manage_servers`) get a "Try the mockup" button in the app bar,
next to the game content one. It opens a fresh mockup game over the real app,
under a bar with an Exit button; nothing of it is kept once they leave
(`lib/mockup/mockup_shell.dart`).

### Selectable and searchable text

All text in the app can be selected and copied (a `SelectionArea` around every
screen, see `GameApp`); the drawing canvas opts out, so a long press or a quick
tap-then-drag there always draws. On the web, `main.dart` turns on Flutter's
semantics: text is then also in the page (hidden), so the browser's
find-in-page and screen readers see it, not just the pixels Flutter paints.

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
  Auth0. Signing in, signing up and servers (create, join, lobby) work; the
  rest of the game follows step by step and reports that it isn't available
  yet.
- `lib/theme/palette.dart`: the shared colour palette.
