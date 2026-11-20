import 'package:flutter/material.dart';

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
  runApp(GameApp(session: FeatureFlags.mockupGameplay ? MockGameSession() : _backendSession()));
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
