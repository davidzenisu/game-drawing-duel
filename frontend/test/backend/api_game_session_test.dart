import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/api_client.dart';
import 'package:frontend/backend/api_game_session.dart';
import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/backend/sketch_json.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/content.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';
import 'package:frontend/game/rules/themes.dart';
import 'package:frontend/game/rules/upgrades.dart';

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
    final backend = FakeBackend()..players['test-token'] = {'id': 'player-uuid-3', 'first_name': 'Sam'};
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
    final backend = FakeBackend()..players['test-token'] = {'id': 'player-uuid-3', 'first_name': 'Sam'};
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
      expect(put.url.path, '/servers/123456/assignments/${knight.id.substring('assignment-'.length)}/drawing');
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

    Future<void> drawAll(ApiGameSession player) async {
      for (final assignment in player.assignments) {
        await player.submitSetupDrawing(assignment, doodle, assignment.prompt.label);
      }
    }

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
      expect(admin.serverNotice, 'Sam cancelled server 123456.');
      expect(backend.requests.last.url.path, '/servers/123456/dismiss');

      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      expect(admin.phase, GamePhase.lobby);
      expect(admin.serverNotice, isNull);
    });

    test('players returning to a cancelled server are told once', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      final sam = (await everyoneJoins()).first;
      await sam.cancelServer();

      final back = await signedUpAgain('alex');
      expect(back.phase, GamePhase.server);
      expect(back.serverNotice, 'Sam cancelled server 123456.');
      final later = await signedUpAgain('alex');
      expect(later.phase, GamePhase.server);
      expect(later.serverNotice, isNull);
    });

    test('a running game cancelled by someone else ends on your next action', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      final sam = await signedUp('sam', 'Sam');
      final preview = await sam.previewServer('123456');
      await sam.joinServer(preview, preview.players[1]);
      await admin.startSetup();
      await sam.refreshServer();
      await drawAll(admin);
      await admin.launch();
      await drawAll(sam);
      await sam.launch();
      expect(sam.phase, GamePhase.daily);

      await sam.cancelServer();
      await expectLater(admin.pull(1), throwsA(isA<ApiException>()));
      expect(admin.phase, GamePhase.server);
      expect(admin.serverNotice, 'Sam cancelled server 123456.');
      expect(admin.pool, isEmpty);
    });

    test('cancelled servers cannot be joined', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
      await admin.cancelServer();
      final sam = await signedUp('sam', 'Sam');
      await expectLater(sam.previewServer('123456'), throwsA(isA<ApiException>()));
    });

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
      expect((sam.day, sam.theme), (1, DailyTheme.forest));
      expect(sam.promptCandidates.map((p) => p.name), ['Alex', 'Robin', 'Kim', 'Jo'], reason: 'anyone but Sam');
      expect(sam.promptTheme, DailyTheme.volcano, reason: "the theme of day 3, the challenger's heroes day");
      expect(sam.promptToDraw, isNull, reason: 'nothing was written yet');

      await admin.refreshServer();
      expect(admin.phase, GamePhase.daily);
      expect(admin.collection.map((o) => o.card.title), ['A legend', 'Knight', 'Basic'], reason: 'rarest first');
      expect(admin.tickets, 10, reason: 'the launch bonus');
      expect(admin.isMockup, isFalse);
      expect(admin.refreshInterval, const Duration(seconds: 5));
    });

    test('pulls spend tickets and add copies to the collection', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await admin.startSetup();
      await drawAll(admin);
      await admin.launch();
      expect(admin.phase, GamePhase.daily);
      expect(admin.gachaStatus.beginnerPullsLeft, 10);

      // The fake hands out the pool in order: Basic, Knight, A legend, …
      final outcomes = await admin.pull(4);
      final pull = backend.requests.last;
      expect(pull.url.path, '/servers/123456/pulls');
      expect(jsonDecode(pull.body), {'count': 4, 'banner': 'standard'});
      expect(outcomes.map((o) => o.card.title), ['Basic', 'Knight', 'A legend', 'Basic']);
      expect(outcomes.map((o) => o.copies), [2, 2, 2, 3]);
      expect(outcomes.every((o) => !o.isNew), isTrue, reason: 'you own your setup drawings');
      expect(admin.tickets, 6);
      expect(admin.gachaStatus.totalPulls, 4);
      final basic = admin.collection.firstWhere((o) => o.card.title == 'Basic');
      expect(basic.copies, 3);
      expect(basic.upgradePoints, 2);
      expect(basic.nextUpgradeCost, 1);

      await expectLater(
        admin.pull(10),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Not enough pulls')),
      );
      expect(admin.tickets, 6);
      await expectLater(
        admin.pull(1, banner: GachaBanner.weekly),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
        reason: 'the weekly banner opens with the first finale',
      );
      expect(backend.bannersPulled.last, 'weekly');
      expect(admin.tickets, 6);

      // Every first upgrade costs a single duplicate, the next ones more.
      expect(admin.upgradesAvailable, 3, reason: 'the basic, the knight and the legend');
      await admin.unlockNextUpgrade(basic);
      expect(backend.requests.last.url.path, '/servers/123456/collection/${basic.card.id}/upgrades');
      expect(basic.unlocked, [UpgradeEffect.shadow]);
      expect(basic.upgradePoints, 1);
      expect(basic.nextUpgradeCost, 2);
      expect(admin.canUpgrade(basic), isFalse, reason: 'no unlocking on credit outside the mockup');
      expect(admin.upgradesAvailable, 2);

      final knight = admin.collection.firstWhere((o) => o.card.title == 'Knight');
      await admin.unlockNextUpgrade(knight);
      await expectLater(
        admin.unlockNextUpgrade(knight),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'You need 1 more duplicate to unlock this')),
      );
    });

    test('the daily loop: prompts, challengers and ending the day', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      final sam = await signedUp('sam', 'Sam');
      final preview = await sam.previewServer('123456');
      await sam.joinServer(preview, preview.players[1]);
      await admin.refreshServer();
      await admin.startSetup();
      await sam.refreshServer();
      for (final player in [admin, sam]) {
        await drawAll(player);
        await player.launch();
      }
      await admin.refreshServer();
      expect(admin.phase, GamePhase.daily);
      expect((admin.canEndDay, admin.canAdvanceDay), (true, true));
      expect((sam.canEndDay, sam.canAdvanceDay), (true, false), reason: 'only the admin skips ahead');

      expect(admin.promptHint, 'a challenger on a volcano day');
      await admin.submitPrompt('  The Owl King ', admin.server.players[2]);
      expect((jsonDecode(backend.requests.last.body) as Map)['subject_position'], 2);
      expect(admin.yourPrompt!.subject.name, 'Robin');
      expect(admin.yourPrompt!.title, 'The Owl King');
      expect(admin.yourPrompt!.theme, DailyTheme.volcano);

      await admin.endDay();
      expect(admin.dayEnded, {admin.you.id});
      expect(admin.day, 1, reason: 'Sam is still playing');
      await sam.refreshDay();
      expect(sam.dayEnded, {admin.you.id});
      await sam.endDay();
      expect(sam.day, 2);
      expect(sam.dayEnded, isEmpty);

      final toDraw = sam.promptToDraw!;
      expect((toDraw.title, toDraw.author.name, toDraw.premade), ('The Owl King', 'Alex', false));
      expect(toDraw.question, 'Who is a challenger on a volcano day?', reason: "the description Alex got");
      await admin.refreshDay();
      expect(admin.promptToDraw!.premade, isTrue, reason: 'Sam wrote nothing');
      expect(admin.promptToDraw!.hint, isNull);

      await sam.submitChallenger(doodle);
      expect(sam.yourChallenger!.title, 'The Owl King');
      expect(sam.yourChallenger!.rarity, Rarity.hero);
      expect(sam.yourChallenger!.sketch, same(doodle));
      expect(sam.challengerDrawn, isTrue);
      expect(sam.pool, isNot(contains(sam.yourChallenger)), reason: 'challengers stay out of the gacha pool');
      expect(sam.challengers.single.card.id, sam.yourChallenger!.id);
      expect((sam.challengers.single.fights, sam.challengers.single.winRate), (0, null));
      await admin.refreshDay();
      expect(admin.challengers, isEmpty, reason: 'Alex has not encountered it');
      expect(sam.tickets, 11, reason: 'a challenger earns a pull');

      await admin.advanceDay();
      expect(admin.day, 3);
      await expectLater(sam.advanceDay(), throwsA(isA<ApiException>()));

      // The free hurry: once a day, a surprise for the target's drawing.
      await sam.refreshDay();
      expect(await admin.sendHurry(sam.server.players[1].copyWith(isYou: false)), isTrue);
      expect(admin.hurrySentTo!.name, 'Sam');
      expect(await admin.sendHurry(admin.server.players[1]), isFalse, reason: 'once a day');
      await sam.refreshDay();
      expect(sam.incomingHurries.single.by, 'Alex');
      expect(sam.incomingHurries.single.atFraction, 0.4);
      expect(admin.incomingHurries, isEmpty);
    });

    test('fighters on day 3, boosts on day 4 and the outcome on day 5', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      final sam = await signedUp('sam', 'Sam');
      final robin = await signedUp('robin', 'Robin');
      for (final (i, player) in [sam, robin].indexed) {
        final preview = await player.previewServer('123456');
        await player.joinServer(preview, preview.players[i + 1]);
      }
      await admin.refreshServer();
      await admin.startSetup();
      final players = [admin, sam, robin];
      for (final player in players) {
        await player.refreshServer();
        await drawAll(player);
        await player.launch();
      }
      Future<void> nextDay() async {
        await admin.advanceDay();
        for (final player in [sam, robin]) {
          await player.refreshDay();
        }
      }

      await nextDay();
      for (final player in players) {
        await player.submitChallenger(doodle);
      }
      await nextDay();

      // Day 3: Alex sends two fighters against Sam's challenger.
      expect(admin.fightChallenger!.artist, 'Sam');
      await admin.submitFighters(admin.collection.take(2).toList());
      final put = backend.requests.lastWhere((r) => r.method == 'PUT');
      expect(put.url.path, '/servers/123456/today/fighters');
      expect((jsonDecode(put.body) as Map)['character_ids'], hasLength(2));
      expect(admin.yourFight!.fighters, hasLength(2));
      expect(admin.yourFight!.challenger.artist, 'Sam');
      final samsChallenger = admin.yourFight!.challenger.id;
      expect(admin.challengers.map((c) => c.card.id), contains(samsChallenger), reason: 'fought against');
      expect(admin.restingCharacterIds, isEmpty);
      for (final player in players) {
        await player.submitChallenger(doodle);
      }

      // Day 4: Alex's two fighters rest until Monday.
      await nextDay();
      final rested = {
        for (final o in admin.collection.take(2))
          if (o.card.rarity != Rarity.basic) o.card.id,
      };
      expect(admin.restingCharacterIds, rested, reason: 'basic ones fight every day');
      expect(admin.availableFighters, hasLength(admin.collection.length - rested.length));

      // Robin boosts Sam's challenger; Sam drew it and can't.
      expect(sam.boostTargets, isEmpty);
      expect(admin.boostTargets, isEmpty, reason: 'Alex fought it');
      final target = robin.boostTargets.single;
      expect(target.challenger.id, samsChallenger);
      expect(target.matchups.single.owner.name, 'Alex');
      expect(robin.canBoost, isTrue);
      expect(robin.challengers.map((c) => c.card.id), isNot(contains(samsChallenger)));
      await robin.boost(target.challenger);
      final post = backend.requests.lastWhere((r) => r.method == 'POST');
      expect(post.url.path, '/servers/123456/today/boosts');
      expect(jsonDecode(post.body), {'challenger_id': samsChallenger});
      expect(robin.boostedChallengerId, samsChallenger);
      expect(robin.canBoost, isFalse);
      expect(robin.challengers.map((c) => c.card.id), contains(samsChallenger), reason: 'boosted');

      // Day 5: decided by the stars, 4 against the boosted challenger's 3 + 1.
      await nextDay();
      final result = admin.yourFightResults.single;
      expect((result.boosts, result.challengerStars), (1, 4));
      expect(result.fightersWin, result.fighterStars > 4);
      expect(sam.yourChallengerResults.single.id, result.id);
      expect(robin.yourFightResults, isEmpty);
      final record = admin.challengers.firstWhere((c) => c.card.id == samsChallenger);
      expect((record.fights, record.wins), (1, result.fightersWin ? 0 : 1));
    });

    test('the finale: vote on a pair, then the weekly hero', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await admin.startSetup();
      await drawAll(admin);
      await admin.launch();
      expect((admin.finale, admin.weeklyHero), (null, null));
      expect(admin.rateUp, isEmpty);

      final [left, right, ...] = [for (final d in backend.drawings.values) d.character];
      backend.finales['123456'] = {
        'pair': {'left': left, 'right': right},
        'votes': 0,
        'pairs': 1,
        'contenders': 2,
      };
      await admin.refreshDay();
      final ballot = admin.finale!;
      expect(ballot.pair!.$1.id, left['id']);
      expect(ballot.pair!.$2.id, right['id']);
      expect((ballot.votes, ballot.pairs, ballot.contenders), (0, 1, 2));
      expect(admin.canVoteFinale, isTrue);

      await admin.voteFinale(ballot.pair!.$2, ballot.pair!.$1);
      final post = backend.requests.lastWhere((r) => r.method == 'POST');
      expect(post.url.path, '/servers/123456/today/finale');
      expect(jsonDecode(post.body), {'chosen_id': right['id'], 'other_id': left['id']});
      expect(admin.finale!.pair, isNull);
      expect(admin.finale!.votes, 1);
      expect(admin.canVoteFinale, isFalse);

      backend.finales.remove('123456');
      backend.weeklyHeroes['123456'] = {'character': right, 'day': 7, 'stars': 5, 'votes': 2};
      await admin.refreshDay();
      expect(admin.finale, isNull);
      final hero = admin.weeklyHero!;
      expect((hero.card.id, hero.day, hero.stars, hero.votes), (right['id'], 7, 5, 2));
      // The hero is rate-up now, with the legends of the same player.
      expect(admin.rateUp, contains(right['id']));
      for (final id in admin.rateUp.difference({right['id']})) {
        final legend = admin.pool.firstWhere((c) => c.id == id);
        expect((legend.rarity, legend.subject), (Rarity.legend, hero.card.subject));
      }
    });

    test('seen tutorials are stored with the account', () async {
      expect(admin.tutorialsSeen, isEmpty);
      await admin.markTutorialSeen('draw');
      await admin.markTutorialSeen('draw');
      expect(admin.tutorialsSeen, {'draw'});
      final puts = backend.requests.where((r) => r.method == 'PUT' && r.url.path.startsWith('/me/tutorials/'));
      expect(puts.map((r) => r.url.path), ['/me/tutorials/draw'], reason: 'once');

      final again = await signedUpAgain('alex');
      expect(again.tutorialsSeen, {'draw'}, reason: 'on another device too');
    });

    test('failing to store a seen tutorial is not an error', () async {
      backend.rejectAll = (status: 500, detail: 'Down');
      await admin.markTutorialSeen('boost');
      expect(admin.tutorialsSeen, {'boost'});
    });

    test('a content entry from an older API names what is missing', () async {
      backend.contentEditors.add('kim');
      final editor = await signedUp('kim', 'Kim');
      // As the API returned them before hints had premade titles.
      backend.hints.add({
        'id': 'content-1',
        'theme': 'volcano',
        'text': 'a sauna regular',
        'created_at': '2026-10-12T10:00:00Z',
      });
      await expectLater(
        editor.contentEntries(DailyTheme.volcano),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Unexpected content entry: "premade_title" is missing.',
          ),
        ),
      );
    });

    test('content editors manage the descriptions and premade titles', () async {
      // Players don't get the content screen.
      expect(admin.canEditContent, isFalse);

      backend.contentEditors.add('kim');
      final editor = await signedUp('kim', 'Kim');
      expect(editor.canEditContent, isTrue);
      final added = await editor.addContent(DailyTheme.volcano, const [
        HintDraft(text: 'a sauna regular', premadeTitle: 'Lord of the Top Bench'),
        HintDraft(text: 'a toast burner', premadeTitle: 'The Toast Incinerator'),
      ]);
      final post = backend.requests.last;
      expect((post.method, post.url.path), ('POST', '/content/hints'));
      expect(jsonDecode(post.body), {
        'theme': 'volcano',
        'hints': [
          {'text': 'a sauna regular', 'premade_title': 'Lord of the Top Bench'},
          {'text': 'a toast burner', 'premade_title': 'The Toast Incinerator'},
        ],
      });
      expect(added.added.map((e) => (e.text, e.premadeTitle)), [
        ('a sauna regular', 'Lord of the Top Bench'),
        ('a toast burner', 'The Toast Incinerator'),
      ]);
      expect(added.added.first.theme, DailyTheme.volcano);
      final again = await editor.addContent(DailyTheme.volcano, const [
        HintDraft(text: 'a toast burner', premadeTitle: 'Another'),
      ]);
      expect(again.added, isEmpty);
      expect(again.skipped, ['a toast burner']);

      final listed = await editor.contentEntries(DailyTheme.volcano);
      expect(backend.requests.last.url.toString(), 'https://api.example/content/hints?theme=volcano');
      expect(listed, hasLength(2));
      expect(await editor.contentEntries(DailyTheme.snow), isEmpty);

      await editor.retireContent(listed.first);
      final delete = backend.requests.last;
      expect((delete.method, delete.url.path), ('DELETE', '/content/hints/${listed.first.id}'));
      expect((await editor.contentEntries(DailyTheme.volcano)).map((e) => e.text), ['a toast burner']);
    });

    test('a reload keeps the upgrades and the chosen element', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await admin.startSetup();
      await drawAll(admin);
      await admin.launch();
      backend.upgrades[('123456', 'player-uuid-1', admin.collection.first.card.id)] = (
        effects: ['shadow', 'light', 'element'],
        element: 'ice',
      );
      final again = await signedUpAgain('alex');
      final legend = again.collection.first;
      expect(legend.unlocked, [UpgradeEffect.shadow, UpgradeEffect.light, UpgradeEffect.element]);
      expect(legend.element, ElementKind.ice);
    });

    test('unlocked effects can be switched off, and stay so after a reload', () async {
      await admin.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await admin.startSetup();
      await drawAll(admin);
      await admin.launch();
      final id = admin.collection.first.card.id;
      backend.upgrades[('123456', 'player-uuid-1', id)] = (effects: ['shadow', 'outline'], element: null);
      final again = await signedUpAgain('alex');
      final owned = again.collection.first;
      expect(owned.shown, [UpgradeEffect.shadow, UpgradeEffect.outline]);

      await again.setEffectShown(owned, UpgradeEffect.outline, shown: false);
      final put = backend.requests.last;
      expect(put.method, 'PUT');
      expect(put.url.path, '/servers/123456/collection/$id/effects');
      expect(jsonDecode(put.body), {
        'hidden': ['outline'],
      });
      expect(owned.hidden, {UpgradeEffect.outline});
      expect(owned.shown, [UpgradeEffect.shadow]);
      expect(FighterEntry.fromOwned(owned).effects, [UpgradeEffect.shadow], reason: 'fighters leave it out too');

      await expectLater(
        again.setEffectShown(owned, UpgradeEffect.light, shown: false),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Unlock light first')),
      );
      expect((await signedUpAgain('alex')).collection.first.hidden, {UpgradeEffect.outline});
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
