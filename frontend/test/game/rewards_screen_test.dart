import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/achievements.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/screens/heroes_menu_screen.dart';
import 'package:frontend/game/screens/rewards_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

/// Summons, with a gift of pulls, until a reward is reached.
Future<void> _summonUntilReached(MockGameSession game) async {
  await game.sendGift(message: 'Pulls', pulls: 200);
  await game.acceptGift(game.gifts.last);
  while (game.achievementsToCollect == 0) {
    await game.pull(1);
  }
}

void main() {
  test('the mockup rewards collecting starter heroes and winning fights, once each', () async {
    final game = await launchedGame(launchDate: firstMonday);
    final keys = game.achievements.map((a) => a.key);
    expect(keys.where((k) => k.startsWith('artist:')), hasLength(game.server.players.length - 1));
    expect(keys, containsAll(['wins:1', 'wins:3', 'wins:10', 'streak:3', 'streak:5']));

    await _summonUntilReached(game);
    final reached = game.achievements.firstWhere((a) => a.collectable);
    final before = game.stars;
    await game.collectAchievement(reached);
    expect(game.stars, before + reached.stars);
    expect(game.achievements.firstWhere((a) => a.key == reached.key).collected, isTrue);
    await game.collectAchievement(reached);
    expect(game.stars, before + reached.stars, reason: 'only once');

    // Win a fight.
    for (var day = 1; day < LoopStep.fight; day++) {
      await game.advanceDay();
    }
    final wins = game.achievements.firstWhere((a) => a.key == 'wins:1');
    expect(wins.progress, 0);
    await game.submitFighters(game.availableFighters.take(4).toList());
    expect(game.achievements.firstWhere((a) => a.key == 'wins:1').done, game.yourFight!.fightersWin);
  });

  testWidgets('the rewards menu shows progress and collects reached rewards', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame(launchDate: firstMonday);
    await _summonUntilReached(game);

    await tester.pumpWidget(MaterialApp(home: HeroesMenuScreen(controller: game)));
    await tester.pump();
    await tester.tap(find.text('Rewards'));
    await tester.pumpAndSettle();
    expect(find.byType(RewardsScreen), findsOneWidget);
    expect(find.text('Starter heroes'), findsOneWidget);
    expect(find.text('First win'), findsNothing, reason: 'further down');
    final reached = game.achievements.firstWhere((a) => a.collectable);
    expect(find.text(reached.title), findsOneWidget, reason: 'ready ones first');
    final before = game.stars;
    await tester.tap(find.text('Collect ${reached.stars}').first);
    await tester.pumpAndSettle();
    expect(game.stars, before + reached.stars);
    await tester.scrollUntilVisible(find.text('First win'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('0/1'), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    await tester.pumpWidget(const SizedBox());
  });

  test('every achievement reads well', () {
    const sam = Achievement(key: 'wins:3', kind: AchievementKind.wins, goal: 3, progress: 1, stars: 5);
    expect((sam.title, sam.description), ('3 wins', 'Win 3 fights you picked the fighters for.'));
  });
}
