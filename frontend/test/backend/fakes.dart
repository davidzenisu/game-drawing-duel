import 'dart:convert';

import 'package:frontend/backend/auth_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAuthClient implements AuthClient {
  FakeAuthClient({this.profile, this.token = 'test-token', this.restoreError});

  AuthProfile? profile;
  final String token;
  final Object? restoreError;
  int signIns = 0;

  @override
  Future<AuthProfile?> restore() async {
    if (restoreError != null) throw restoreError!;
    return profile;
  }

  @override
  Future<void> signIn() async => signIns++;

  @override
  Future<String> accessToken() async => token;
}

/// A fake backend: `/me` answers 404 until a PUT signs the player up.
class FakeBackend {
  FakeBackend([this._player]);

  Map<String, Object?>? _player;
  final List<http.Request> requests = [];

  MockClient get client => MockClient((request) async {
    requests.add(request);
    if (request.url.path != '/me') return _json(404, {'detail': 'Not Found'});
    switch (request.method) {
      case 'GET':
        return _player == null ? _json(404, {'detail': 'Not signed up yet'}) : _json(200, _player);
      case 'PUT':
        final body = jsonDecode(request.body) as Map<String, Object?>;
        _player = {'id': 7, 'first_name': body['first_name'], 'created_at': '2026-10-09T10:00:00Z'};
        return _json(200, _player);
      default:
        return _json(405, {'detail': 'Method Not Allowed'});
    }
  });

  static http.Response _json(int status, Object? body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}
