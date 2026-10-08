import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/mockup/logic/game_controller.dart';
import 'package:frontend/mockup/logic/models.dart';
import 'package:frontend/mockup/logic/setup_plan.dart';
import 'package:frontend/mockup/logic/upgrades.dart';

const _doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

GameController launchedGame({int seed = 1}) {
  final game = GameController(seed: seed)
    ..signUp('Pat')
    ..createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
  while (game.simulateNextJoin()) {}
  game.startSetup();
  for (final assignment in game.assignments) {
    game.submitSetupDrawing(assignment, _doodle, 'Title');
  }
  game.launch();
  return game;
}

void main() {
  test('creating a server generates a 6-digit code and an admin roster', () {
    final game = GameController(seed: 1)
      ..signUp('Pat')
      ..createServer(['Alex', 'Sam', 'Robin', 'Kim']);
    expect(game.phase, GamePhase.lobby);
    expect(game.server.code, matches(RegExp(r'^\d{6}$')));
    expect(game.server.isAdmin, isTrue);
    expect(game.server.players.first.isYou, isTrue);
    expect(game.server.everyoneJoined, isFalse);
  });

  test('joining a server claims a seat from the prepopulated roster', () {
    final game = GameController(seed: 1)..signUp('Pat');
    final roster = game.previewServer('123456');
    expect(roster.length, inInclusiveRange(SetupPlan.minPlayers, SetupPlan.maxPlayers));
    final seat = roster.firstWhere((p) => p.name == 'Pat');
    game.joinServer('123456', roster, seat);
    expect(game.you.id, seat.id);
    expect(game.server.isAdmin, isFalse);
    expect(game.server.players.where((p) => p.isYou), hasLength(1));
  });

  test('the alter unlocks after the basic drawing', () {
    final game = GameController(seed: 1)
      ..signUp('Pat')
      ..createServer(['Alex', 'Sam', 'Robin', 'Kim']);
    game.startSetup();
    final alter = game.assignments.firstWhere((a) => a.prompt == SetupPrompt.alter);
    expect(game.isUnlocked(alter), isFalse);
    game.submitSetupDrawing(game.assignments.first, _doodle, 'Basic');
    expect(game.isUnlocked(alter), isTrue);
  });

  test('launching fills the pool and starts day 1', () {
    final game = launchedGame();
    final players = game.server.players.length;
    final launchPool = SetupPlan.poolAtLaunch(players).values.reduce((a, b) => a + b);
    expect(game.phase, GamePhase.daily);
    expect(game.day, 1);
    expect(game.tickets, GameController.launchBonus);
    expect(game.todaysChallengers, hasLength(players - 1));
    expect(game.pool, hasLength(launchPool + players - 1));
  });

  test('daily challenger, pulls, upgrades and duels', () {
    final game = launchedGame();
    game.submitChallenger(_doodle, 'Beach body');
    expect(game.tickets, GameController.launchBonus + 1);
    game.submitChallenger(_doodle, 'Twice');
    expect(game.tickets, GameController.launchBonus + 1, reason: 'one challenger per day');

    final outcomes = game.pull(10);
    expect(outcomes, hasLength(10));
    expect(outcomes.any((o) => o.card.rarity.stars >= 3), isTrue);
    expect(game.tickets, 1);
    expect(() => game.pull(2), throwsStateError);

    // Duplicates turn into upgrade points.
    while (!game.collection.any((o) => o.canUpgrade)) {
      game.nextDay();
      game.submitChallenger(_doodle, 'More');
      game.pull(game.tickets);
    }
    final owned = game.collection.firstWhere((o) => o.canUpgrade);
    game.unlockNextUpgrade(owned);
    expect(owned.unlocked, [UpgradeEffect.shadow]);

    final result = game.duel(owned, game.todaysChallengers.first);
    final before = game.tickets;
    final rewarded = game.recordDuel(result);
    expect(rewarded, result.leftWins);
    expect(game.tickets, before + (result.leftWins ? 1 : 0));
  });

  test('hurries cost a pull and can only be sent once per player per day', () {
    final game = launchedGame();
    final target = game.otherPlayers.first;
    expect(game.sendHurry(target), isTrue);
    expect(game.sendHurry(target), isFalse);
    expect(game.tickets, GameController.launchBonus - GameController.hurryCost);
    game.nextDay();
    expect(game.hurriedToday, isEmpty);
    expect(game.day, 2);
  });
}
