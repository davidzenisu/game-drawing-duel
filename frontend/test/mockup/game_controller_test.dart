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

  test('launching fills the pool, the rosters and starts day 1', () {
    final game = launchedGame();
    final players = game.server.players.length;
    final launchPool = SetupPlan.poolAtLaunch(players).values.reduce((a, b) => a + b);
    expect(game.phase, GamePhase.daily);
    expect(game.day, 1);
    expect(game.tickets, GameController.launchBonus);
    expect(game.pool, hasLength(launchPool));
    // Your own setup drawings land in your roster.
    expect(game.collection.map((o) => o.card.id), unorderedEquals(game.assignments.map((a) => a.id)));
  });

  test('day 1 only unlocks the prompt step', () {
    final game = launchedGame();
    expect(game.yourPrompt, isNull);
    expect(game.promptSubject.isYou, isFalse);
    expect(game.promptToDraw, isNull);
    expect(game.fightChallenger, isNull);
    expect(game.fightsToVote, isEmpty);
    game.submitPrompt('Sunburnt');
    expect(game.yourPrompt?.title, 'Sunburnt');
    expect(game.yourPrompt?.theme, game.theme);
  });

  test('the 4 day loop: prompt, draw, fighters, vote and results', () {
    final game = launchedGame();
    final you = game.you;

    // Day 1: write a prompt.
    game.submitPrompt('Sunburnt');

    // Day 2: draw someone else's prompt from yesterday.
    game.nextDay();
    final toDraw = game.promptToDraw!;
    expect(toDraw.author.isYou, isFalse);
    expect(toDraw.day, 1);
    expect(toDraw.subject.id, isNot(you.id));
    final tickets = game.tickets;
    game.submitChallenger(_doodle);
    expect(game.tickets, tickets + 1);
    expect(game.yourChallenger?.title, toDraw.title);
    game.submitChallenger(_doodle);
    expect(game.tickets, tickets + 1, reason: 'one challenger per day');
    game.submitPrompt('Day two prompt');

    // Day 3: pick up to four fighters against one new challenger.
    game.nextDay();
    final challenger = game.fightChallenger!;
    expect(challenger.day, 2);
    expect(challenger.artist, isNot(you.name));
    expect(() => game.submitFighters(game.collection.take(5).toList()), throwsArgumentError);
    game.submitFighters(game.collection.take(4).toList());
    expect(game.yourFight?.fighters, hasLength(4));

    // Day 4: vote on the others' fights, see the results of yours.
    game.nextDay();
    final toVote = game.fightsToVote;
    // One player fights your challenger, everyone else's fight is up for your vote.
    expect(toVote, hasLength(game.otherPlayers.length - 1));
    expect(toVote.every((f) => !f.owner.isYou && f.challenger.artist != you.name), isTrue);
    game.vote(toVote.first, fightersWin: true);
    expect(game.hasVoted(toVote.first), isTrue);
    expect(game.votesLeft, toVote.length - 1);

    final fights = game.yourFightResults;
    expect(fights, hasLength(1));
    expect(fights.single.votes, hasLength(game.otherPlayers.length));
    // Somebody fought the challenger you drew two days ago.
    expect(game.yourChallengerResults, hasLength(1));
    expect(game.yourChallengerResults.first.challenger.day, 2);
  });

  test('pulls turn duplicates into upgrade points', () {
    final game = launchedGame();
    final outcomes = game.pull(10);
    expect(outcomes, hasLength(10));
    expect(outcomes.any((o) => o.card.rarity.stars >= 3), isTrue);
    expect(game.tickets, 0);
    expect(() => game.pull(1), throwsStateError);

    while (!game.collection.any((o) => o.canUpgrade)) {
      game.nextDay();
      if (game.promptToDraw != null) game.submitChallenger(_doodle);
      game.pull(game.tickets);
    }
    final owned = game.collection.firstWhere((o) => o.canUpgrade);
    game.unlockNextUpgrade(owned);
    expect(owned.unlocked, [UpgradeEffect.shadow]);
  });

  test('a hurry is free and can be sent once per day', () {
    final game = launchedGame();
    final tickets = game.tickets;
    expect(game.sendHurry(game.otherPlayers.first), isTrue);
    expect(game.sendHurry(game.otherPlayers.last), isFalse);
    expect(game.tickets, tickets);
    expect(game.hurrySentTo, game.otherPlayers.first);
    game.nextDay();
    expect(game.hurrySentTo, isNull);
    expect(game.day, 2);
  });
}
