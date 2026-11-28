import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'backend/api_client.dart';
import 'backend/api_game_session.dart';
import 'backend/auth0_auth_client.dart';
import 'feature_flags.dart';
import 'game/game_app.dart';
import 'game/game_session.dart';
import 'mockup/mock_game_session.dart';

const _auth0Domain = String.fromEnvironment('AUTH0_DOMAIN');
const _auth0ClientId = String.fromEnvironment('AUTH0_CLIENT_ID');
const _auth0Audience = String.fromEnvironment('AUTH0_AUDIENCE');
const _apiUrl = String.fromEnvironment('API_URL');

void main() {
  // The game handles the browser's back button itself (`BackGuard`), so
  // Flutter's own browser history must stay out of it.
  setUrlStrategy(null);
  final app = GameApp(session: FeatureFlags.mockupGameplay ? MockGameSession() : _backendSession());
  // TEMPORARY (#349): with ?pentest, tells web/pen_debug.js what Flutter
  // gets from a pen; remove before merging.
  runApp(kIsWeb && Uri.base.query.contains('pentest') ? _PenLog(child: app) : app);
}

class _PenLog extends StatelessWidget {
  const _PenLog({required this.child});

  final Widget child;

  static void _log(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus && event.kind != PointerDeviceKind.invertedStylus) return;
    final change = switch (event) {
      PointerDownEvent() => 'down',
      PointerMoveEvent() => 'move',
      PointerUpEvent() => 'up',
      PointerHoverEvent() => 'hover',
      PointerCancelEvent() => 'cancel',
      _ => 'other',
    };
    debugPrint('FLT $change ${event.buttons}');
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _log,
    onPointerMove: _log,
    onPointerUp: _log,
    onPointerHover: _log,
    onPointerCancel: _log,
    child: child,
  );
}

GameSession _backendSession() {
  final missing = [
    if (_auth0Domain.isEmpty) 'AUTH0_DOMAIN',
    if (_auth0ClientId.isEmpty) 'AUTH0_CLIENT_ID',
    if (_auth0Audience.isEmpty) 'AUTH0_AUDIENCE',
    if (_apiUrl.trim().isEmpty) 'API_URL',
  ];
  final session = missing.isNotEmpty
      ? ApiGameSession(api: null, signInProblem: 'Sign-in is not configured (missing ${missing.join(', ')}).')
      : ApiGameSession(
          api: ApiClient(
            baseUrl: _apiUrl,
            auth: Auth0AuthClient(domain: _auth0Domain, clientId: _auth0ClientId, audience: _auth0Audience),
          ),
        );
  session.start();
  return session;
}
