# frontend

## Auth0

The web app reads `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, and `API_URL` at build time
from `config/config.json` using Flutter's `--dart-define-from-file` option. Start
local development by creating the ignored config file from the example:

```sh
cp config/config.json.example config/config.json
```

Replace the example values with your Auth0 domain and client ID, then run the
VS Code **Flutter: Frontend (Codespaces)** launch configuration or start Flutter
with `flutter run -d chrome --web-port 7357 --dart-define-from-file=config/config.json`.
`API_URL` is the API base URL; the app appends `/drawing` when loading items. The
example uses the local Functions host at `http://localhost:7071`.

Register `http://localhost:7357` in the Auth0 application's **Allowed Callback
URLs**, **Allowed Logout URLs**, and **Allowed Web Origins**. Add the production
origin to the same settings.

The Azure Static Web Apps workflow reads the GitHub Actions repository
variables `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, and `API_URL`, writes a temporary
JSON defines file, and passes it to the release build. Set all three repository
variables for deployment. These values are included in the client-side app, so
they are not secrets.

## Mockup gameplay loop

The app can run an offline mockup of the gameplay loop described in
`docs/concept` (account creation, server creation/join, initial drawing setup,
daily challenger drawing, gacha pulls, duplicate upgrades and duels). Everything
happens in memory within a single session; the other players are simulated and
no backend, database or Auth0 is used.

Enable it with the `MOCKUP_GAMEPLAY` feature flag, either in
`config/config.json` (`"MOCKUP_GAMEPLAY": true`) or directly:

```sh
flutter run -d chrome --dart-define=MOCKUP_GAMEPLAY=true
```

The flag defaults to `false`, so regular builds are unaffected. The mockup lives
in `lib/mockup`, the shared colour palette in `lib/theme/palette.dart`.
