import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/heroes_menu_screen.dart';
import 'package:frontend/game/screens/rewards_screen.dart';

import '../helpers.dart';
import '../mockup/mock_achievements_test.dart' show summonUntilReached;

void main() {
  testWidgets('the rewards menu shows progress and collects reached rewards', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame(launchDate: firstMonday);
    await summonUntilReached(game);

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
}
