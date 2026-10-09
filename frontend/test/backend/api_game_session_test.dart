import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/api_client.dart';
import 'package:frontend/backend/api_game_session.dart';
import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/game_session.dart';

import 'fakes.dart';

ApiGameSession sessionWith(FakeAuthClient auth, FakeBackend backend) => ApiGameSession(
  api: ApiClient(baseUrl: 'https://api.example/', auth: auth, httpClient: backend.client),
);

void main() {
  test('without a previous sign-in, the player has to sign in', () async {
    final auth = FakeAuthClient();
    final backend = FakeBackend();
    final session = sessionWith(auth, backend);
    expect(session.phase, GamePhase.loading);

    await session.start();
    expect(session.phase, GamePhase.signIn);
    expect(session.signInProblem, isNull);
    expect(backend.requests, isEmpty);

    await session.signIn();
    expect(auth.signIns, 1);
  });

  test('a new account goes to signup, prefilled from the social login', () async {
    final backend = FakeBackend();
    final session = sessionWith(
      FakeAuthClient(
        profile: const AuthProfile(givenName: 'Pat', name: 'Pat Doe'),
      ),
      backend,
    );

    await session.start();
    expect(session.phase, GamePhase.signup);
    expect(session.suggestedFirstName, 'Pat');

    final request = backend.requests.single;
    expect(request.method, 'GET');
    expect(request.url.toString(), 'https://api.example/me');
    expect(request.headers['Authorization'], 'Bearer test-token');
  });

  test('signing up creates the player and moves on', () async {
    final backend = FakeBackend();
    final session = sessionWith(FakeAuthClient(profile: const AuthProfile(name: 'Pat Doe')), backend);
    await session.start();

    await session.signUp('  Patricia ');
    expect(session.phase, GamePhase.server);
    expect(session.you.name, 'Patricia');
    expect(session.you.isYou, isTrue);

    final put = backend.requests.last;
    expect(put.method, 'PUT');
    expect(put.body, '{"first_name":"Patricia"}');
    expect(put.headers['Content-Type'], startsWith('application/json'));
  });

  test('a returning player skips the signup', () async {
    final backend = FakeBackend({'id': 3, 'first_name': 'Sam', 'created_at': '2026-10-01T00:00:00Z'});
    final session = sessionWith(FakeAuthClient(profile: const AuthProfile(nickname: 'sam')), backend);

    await session.start();
    expect(session.phase, GamePhase.server);
    expect(session.you.name, 'Sam');
  });

  test('a failing sign-in is shown on the sign-in screen', () async {
    final session = sessionWith(FakeAuthClient(restoreError: Exception('popup blocked')), FakeBackend());
    await session.start();
    expect(session.phase, GamePhase.signIn);
    expect(session.signInProblem, contains('popup blocked'));
  });

  test('a missing configuration is explained instead of crashing', () async {
    final session = ApiGameSession(api: null, signInProblem: 'Sign-in is not configured (missing API_URL).');
    await session.start();
    expect(session.phase, GamePhase.signIn);
    expect(session.signInProblem, contains('API_URL'));
    await expectLater(session.signIn(), throwsStateError);
  });

  test('the rest of the game is not available yet', () async {
    final session = sessionWith(FakeAuthClient(), FakeBackend());
    await expectLater(session.createServer(['Sam']), throwsA(isA<NotAvailableYet>()));
    await expectLater(session.previewServer('123456'), throwsA(isA<NotAvailableYet>()));
    expect(session.isMockup, isFalse);
  });

  test('profile first names fall back sensibly', () {
    expect(const AuthProfile(givenName: 'Pat', name: 'Patricia Doe').firstName, 'Pat');
    expect(const AuthProfile(name: 'Patricia Doe').firstName, 'Patricia');
    expect(const AuthProfile(nickname: 'pd').firstName, 'pd');
    expect(const AuthProfile().firstName, '');
  });
}
