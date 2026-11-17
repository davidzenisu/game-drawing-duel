import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/player_stats_screen.dart';

import '../helpers.dart';

void main() {
  test('tied players share a place, the next one skips theirs', () {
    final [a, b, c, d] = const [
      Player(id: 'a', name: 'A'),
      Player(id: 'b', name: 'B'),
      Player(id: 'c', name: 'C'),
      Player(id: 'd', name: 'D'),
    ];
    final stat = PlayerStat.rank(PlayerStatKind.mostWins, [(a, 1), (b, 3), (c, 1), (d, 3)]);
    expect(
      [for (final p in stat.players) (p.player.name, p.value, p.place)],
      [('B', 3, 1), ('D', 3, 1), ('A', 1, 3), ('C', 1, 3)],
    );
  });

  testWidgets('the player stats rank every player by the stat picked, for a period', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await launchedGame(launchDate: firstMonday);
    await controller.advanceDay();

    await tester.pumpWidget(MaterialApp(home: PlayerStatsScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.text('Days 1 to 2, so far. Once the week is over, every first place gets 3 ★.'), findsOneWidget);
    final week = (await controller.playerStats(StatPeriod.week))!;
    final stars = week.stats.firstWhere((s) => s.kind == PlayerStatKind.starsEarned);
    expect(find.text(PlayerStatKind.starsEarned.description), findsOneWidget);
    for (final placed in stars.players) {
      expect(find.text(placed.player.isYou ? '${placed.player.name} (you)' : placed.player.name), findsOneWidget);
    }

    // Another stat.
    await tester.tap(find.text('Busiest'));
    await tester.pumpAndSettle();
    expect(find.text(PlayerStatKind.busiest.description), findsOneWidget);
    final busiest = week.stats.firstWhere((s) => s.kind == PlayerStatKind.busiest);
    expect(find.text('${busiest.players.first.value} steps'), findsWidgets);

    // No last week yet.
    await tester.tap(find.text('Last week'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No finished week yet'), findsOneWidget);

    // All time.
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('Days 1 to 2: every day since the start.'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
  });

  testWidgets("last week's first places got stars", (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await launchedGame(launchDate: firstMonday);
    for (var day = 1; day < 8; day++) {
      await controller.advanceDay();
    }
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerStatsScreen(controller: controller, period: StatPeriod.lastWeek),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Days 1 to 7. Every first place got 3 ★ as a gift.'), findsOneWidget);
    final last = (await controller.playerStats(StatPeriod.lastWeek))!;
    final firsts = last.stats.first.players.where((p) => p.place == 1 && p.value > 0);
    expect(find.text('+3 ★'), findsNWidgets(firsts.length));
    expect(find.byIcon(Icons.emoji_events_rounded), findsNWidgets(firsts.length));
  });
}
