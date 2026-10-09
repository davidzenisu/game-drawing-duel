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

    final put = backend.requests.firstWhere((r) => r.method == 'PUT');
    expect(put.body, '{"first_name":"Patricia"}');
    expect(put.headers['Content-Type'], startsWith('application/json'));
  });

  test('signing out returns to the sign-in', () async {
    final auth = FakeAuthClient(profile: const AuthProfile(givenName: 'Sam'));
    final backend = FakeBackend()..players['test-token'] = {'id': 3, 'first_name': 'Sam'};
    final session = sessionWith(auth, backend);
    await session.start();
    expect(session.phase, GamePhase.server);

    await session.signOut();
    expect(auth.signOuts, 1);
    expect(session.phase, GamePhase.signIn);
    expect(session.suggestedFirstName, isEmpty);
    expect(() => session.you, throwsStateError);
  });

  test('a returning player skips the signup', () async {
    final backend = FakeBackend()..players['test-token'] = {'id': 3, 'first_name': 'Sam'};
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

  group('servers', () {
    late FakeBackend backend;
    late ApiGameSession admin;

    Future<ApiGameSession> signedUp(String token, String name) async {
      final session = ApiGameSession(
        api: ApiClient(
          baseUrl: 'https://api.example',
          auth: FakeAuthClient(token: token, profile: const AuthProfile()),
          httpClient: backend.client,
        ),
      );
      await session.start();
      await session.signUp(name);
      return session;
    }

    setUp(() async {
      backend = FakeBackend();
      admin = await signedUp('alex', 'Alex');
    });

    test('creating a server opens its lobby with you as admin', () async {
      expect(admin.phase, GamePhase.server);
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      expect(admin.phase, GamePhase.lobby);
      expect(admin.server.code, '123456');
      expect(admin.server.isAdmin, isTrue);
      expect(admin.server.players.map((p) => p.name), ['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
      expect(admin.you.name, 'Alex');
      expect(admin.you.isYou, isTrue);
      expect(admin.server.joined, {admin.you.id});
      expect(admin.otherPlayers, hasLength(4));
    });

    test('test sessions are created as such and can start without everyone', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      expect(backend.requests.last.body, contains('"is_test":true'));
      expect(admin.server.isTest, isTrue);
      expect(admin.server.everyoneJoined, isFalse);
      expect(admin.server.canStart, isTrue);
    });

    test('regular servers wait for everyone', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      expect(backend.requests.last.body, contains('"is_test":false'));
      expect(admin.server.isTest, isFalse);
      expect(admin.server.canStart, isFalse);
    });

    test('friends preview the roster, claim a seat and show up in the lobby', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      final sam = await signedUp('sam', 'Sam');

      final preview = await sam.previewServer('123456');
      expect(preview.isAdmin, isFalse);
      expect(preview.joined, {'seat-0'});
      expect(preview.players.where((p) => p.isYou), isEmpty);

      await sam.joinServer(preview, preview.players[1]);
      expect(sam.phase, GamePhase.lobby);
      expect(sam.you.name, 'Sam');
      expect(sam.server.joined, {'seat-0', 'seat-1'});
      expect(backend.requests.last.url.path, '/servers/123456/seats/1/claim');

      await admin.refreshLobby();
      expect(admin.server.joined, {'seat-0', 'seat-1'});
    });

    test('a taken seat is rejected with the API message', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      final sam = await signedUp('sam', 'Sam');
      final kim = await signedUp('kim', 'Kim');
      final preview = await kim.previewServer('123456');
      await sam.joinServer(await sam.previewServer('123456'), preview.players[1]);

      await expectLater(
        kim.joinServer(preview, preview.players[1]),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'This seat is taken')),
      );
      expect(kim.phase, GamePhase.server);
    });

    test('coming back opens the lobby of your newest server', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      final again = ApiGameSession(
        api: ApiClient(
          baseUrl: 'https://api.example',
          auth: FakeAuthClient(token: 'alex', profile: const AuthProfile()),
          httpClient: backend.client,
        ),
      );
      await again.start();
      expect(again.phase, GamePhase.lobby);
      expect(again.server.code, '123456');
    });

    test('unknown codes are reported', () async {
      await expectLater(admin.previewServer('999999'), throwsA(isA<ApiException>()));
    });

    test('the drawings are not available yet', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      await expectLater(admin.startSetup(), throwsA(isA<NotAvailableYet>()));
      expect(admin.isMockup, isFalse);
      expect(admin.lobbyRefreshInterval, const Duration(seconds: 5));
    });
  });

  test('profile first names fall back sensibly', () {
    expect(const AuthProfile(givenName: 'Pat', name: 'Patricia Doe').firstName, 'Pat');
    expect(const AuthProfile(name: 'Patricia Doe').firstName, 'Patricia');
    expect(const AuthProfile(nickname: 'pd').firstName, 'pd');
    expect(const AuthProfile().firstName, '');
  });

  group('a rejected sign-in', () {
    test('a first sign-in reuses the identity provider session', () async {
      final auth = FakeAuthClient();
      final session = sessionWith(auth, FakeBackend());
      await session.start();
      await session.signIn();
      expect(auth.freshSignIns, [false]);
    });

    test('a token the API rejects leads to a fresh sign-in', () async {
      final auth = FakeAuthClient(profile: const AuthProfile(givenName: 'Pat'));
      final backend = FakeBackend()..rejectAll = (status: 401, detail: 'Invalid access token');
      final session = sessionWith(auth, backend);

      await session.start();
      expect(session.phase, GamePhase.signIn);
      expect(session.signInProblem, contains('Invalid access token'));

      await session.signIn();
      expect(auth.freshSignIns, [true], reason: 'retrying must not reuse the rejected session');
    });

    test('a missing permission leads to a fresh sign-in', () async {
      final auth = FakeAuthClient(profile: const AuthProfile(givenName: 'Pat'));
      final backend = FakeBackend()..rejectAll = (status: 403, detail: 'Missing permission read:api');
      final session = sessionWith(auth, backend);
      await session.start();
      expect(session.signInProblem, contains('Missing permission read:api'));
      await session.signIn();
      expect(auth.freshSignIns, [true]);
    });

    test('a token that cannot be fetched leads to a fresh sign-in', () async {
      final auth = FakeAuthClient(profile: const AuthProfile(), tokenError: Exception('login_required'));
      final session = sessionWith(auth, FakeBackend());
      await session.start();
      expect(session.phase, GamePhase.signIn);
      expect(session.signInProblem, contains('login_required'));
      await session.signIn();
      expect(auth.freshSignIns, [true]);
    });

    test('a token rejected mid-game returns to the sign-in', () async {
      final auth = FakeAuthClient(profile: const AuthProfile());
      final backend = FakeBackend();
      final session = sessionWith(auth, backend);
      await session.start();
      await session.signUp('Pat');
      expect(session.phase, GamePhase.server);

      backend.rejectAll = (status: 401, detail: 'Invalid access token');
      await expectLater(session.createServer(['Sam', 'Robin', 'Kim', 'Jo']), throwsA(isA<SignInRequired>()));
      expect(session.phase, GamePhase.signIn);
      expect(() => session.you, throwsStateError);
      await session.signIn();
      expect(auth.freshSignIns, [true]);
    });

    test('other API errors keep you where you are', () async {
      final backend = FakeBackend();
      final session = sessionWith(FakeAuthClient(profile: const AuthProfile()), backend);
      await session.start();
      await session.signUp('Pat');
      await expectLater(session.previewServer('999999'), throwsA(isA<ApiException>()));
      expect(session.phase, GamePhase.server);
      expect(session.signInProblem, isNull);
    });
  });
}
