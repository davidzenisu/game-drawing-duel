# frontend

## Auth0

The web app reads `AUTH0_DOMAIN` and `AUTH0_CLIENT_ID` at build time from
`config/config.json` using Flutter's `--dart-define-from-file` option. Start local
development by creating the ignored config file from the example:

```sh
cp config/config.json.example config/config.json
```

Replace the example values with your Auth0 domain and client ID, then run the
VS Code **Flutter: Frontend (Codespaces)** launch configuration or start Flutter
with `flutter run -d chrome --web-port 7357 --dart-define-from-file=config/config.json`.

Register `http://localhost:7357` in the Auth0 application's **Allowed Callback
URLs**, **Allowed Logout URLs**, and **Allowed Web Origins**. Add the production
origin to the same settings.

The Azure Static Web Apps workflow reads the GitHub Actions repository
variables `AUTH0_DOMAIN` and `AUTH0_CLIENT_ID`, writes a temporary JSON defines
file, and passes it to the release build. These values are included in the
client-side app, so they are not secrets.
