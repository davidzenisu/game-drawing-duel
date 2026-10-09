import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/api_client.dart';
import 'package:frontend/backend/api_game_session.dart';
import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/backend/sketch_json.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';

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

    Future<ApiGameSession> signedUpAgain(String token) async {
      final session = ApiGameSession(
        api: ApiClient(
          baseUrl: 'https://api.example',
          auth: FakeAuthClient(token: token, profile: const AuthProfile()),
          httpClient: backend.client,
        ),
      );
      await session.start();
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

      await admin.refreshServer();
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
      final again = await signedUpAgain('alex');
      expect(again.phase, GamePhase.lobby);
      expect(again.server.code, '123456');
    });

    test('unknown codes are reported', () async {
      await expectLater(admin.previewServer('999999'), throwsA(isA<ApiException>()));
    });

    Future<List<ApiGameSession>> everyoneJoins() async {
      final friends = <ApiGameSession>[];
      for (final (i, name) in ['Sam', 'Robin', 'Kim', 'Jo'].indexed) {
        final friend = await signedUp(name.toLowerCase(), name);
        final preview = await friend.previewServer('123456');
        await friend.joinServer(preview, preview.players[i + 1]);
        friends.add(friend);
      }
      return friends;
    }

    test('only the admin can start, and everyone follows into the setup', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      final friends = await everyoneJoins();
      final sam = friends.first;
      expect(sam.server.canStart, isFalse, reason: 'only the admin starts');

      await admin.refreshServer();
      expect(admin.server.canStart, isTrue);
      await admin.startSetup();
      expect(backend.requests.last.url.path, '/servers/123456/assignments');
      expect(admin.phase, GamePhase.setup);

      await sam.refreshServer();
      expect(sam.phase, GamePhase.setup);
      expect(sam.assignments.map((a) => a.prompt), SetupPlan.promptsFor(5));
      expect(sam.assignments.map((a) => a.subject.name), ['Robin', 'Robin', 'Kim', 'Jo', 'Alex', 'Robin']);
      final alter = sam.assignments[1];
      expect(alter.basedOn, sam.assignments[0].id);
      expect(sam.isUnlocked(alter), isFalse, reason: 'the basic is not drawn yet');
    });

    test('a test session starts with whoever joined', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await admin.startSetup();
      expect(admin.phase, GamePhase.setup);
      expect(admin.assignments.map((a) => a.prompt), SetupPlan.testPrompts);
      expect(admin.assignments.map((a) => a.subject.isYou), everyElement(isFalse), reason: 'the others, joined or not');
      expect(admin.assignments.map((a) => a.subject.id).toSet(), hasLength(3));
    });

    test('coming back during the setup opens your assignments', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await admin.startSetup();
      final again = await signedUpAgain('alex');
      expect(again.phase, GamePhase.setup);
      expect(again.assignments, hasLength(3));
    });

    const doodle = Sketch([
      Stroke(color: Color(0xFF000000), width: 0.016, points: [Offset(0.1, 0.2), Offset(0.3, 0.4)]),
    ]);

    test('setup drawings are uploaded with their title', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await admin.startSetup();
      final knight = admin.assignments[1];
      expect(admin.setupDrawing(knight), isNull);

      await admin.submitSetupDrawing(knight, doodle, '  Sir Alex ');
      final put = backend.requests.last;
      expect(put.method, 'PUT');
      expect(put.url.path, '/servers/123456/assignments/${knight.id.split('-').last}/drawing');
      expect(jsonDecode(put.body), {'title': 'Sir Alex', 'sketch': SketchJson.encode(doodle)});

      final card = admin.setupDrawing(knight)!;
      expect(card.title, 'Sir Alex');
      expect(card.rarity, Rarity.adventurer);
      expect(card.prompt, SetupPrompt.knight.label);
      expect((card.artist, card.subject), ('Alex', knight.subject.name));
      expect(card.sketch, same(doodle), reason: 'no need to download what you just drew');
      expect(admin.setupComplete, isFalse);
    });

    test('coming back during the setup loads your drawings', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await admin.startSetup();
      await admin.submitSetupDrawing(admin.assignments.first, doodle, 'Basic');

      final again = await signedUpAgain('alex');
      expect(again.phase, GamePhase.setup);
      final card = again.setupDrawing(again.assignments.first)!;
      expect(card.title, 'Basic');
      expect(card.sketch.strokes.single.points, doodle.strokes.single.points);
      expect(again.setupDrawing(again.assignments[1]), isNull);
    });

    test('cancelling the setup sends everyone back to the server screen', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      final sam = (await everyoneJoins()).first;
      await admin.startSetup();
      await sam.refreshServer();
      expect(sam.phase, GamePhase.setup);

      await sam.cancelServer();
      expect(backend.requests.last.method, 'DELETE');
      expect(backend.requests.last.url.path, '/servers/123456');
      expect(sam.phase, GamePhase.server);
      expect(sam.serverNotice, isNull, reason: 'Sam knows, Sam cancelled');
      expect(sam.assignments, isEmpty);

      await admin.refreshServer();
      expect(admin.phase, GamePhase.server);
      expect(admin.serverNotice, 'Server 123456 was cancelled.');

      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      expect(admin.phase, GamePhase.lobby);
      expect(admin.serverNotice, isNull);
    });

    Future<void> drawAll(ApiGameSession player) async {
      for (final assignment in player.assignments) {
        await player.submitSetupDrawing(assignment, doodle, assignment.prompt.label);
      }
    }

    test('the game launches once everyone finished their drawings', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await admin.startSetup();
      final sam = await signedUp('sam', 'Sam');
      final preview = await sam.previewServer('123456');
      await sam.joinServer(preview, preview.players[1]);
      expect(sam.phase, GamePhase.setup, reason: 'joining late, Sam draws along');

      await drawAll(admin);
      await admin.launch();
      expect(admin.phase, GamePhase.setup);
      expect(admin.waitingForLaunch, isTrue);
      expect(backend.requests.where((r) => r.method == 'POST').last.url.path, '/servers/123456/setup/done');

      await drawAll(sam);
      await sam.refreshServer();
      expect(sam.server.setupDone, {admin.server.players.first.id});
      await sam.launch();
      expect(sam.phase, GamePhase.daily);
      expect(sam.pool, hasLength(6));
      expect(sam.collection.map((o) => o.card.artist), everyElement('Sam'));
      expect(sam.collection, hasLength(3));
      expect(sam.promptSubject, isNull, reason: 'the daily loop comes later');

      await admin.refreshServer();
      expect(admin.phase, GamePhase.daily);
      expect(admin.collection.map((o) => o.card.title), ['Basic', 'Knight', 'A legend']);
      expect(admin.isMockup, isFalse);
      expect(admin.refreshInterval, const Duration(seconds: 5));
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
