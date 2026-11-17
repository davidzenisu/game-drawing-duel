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
    final stat = PlayerStat.rank(PlayerStatKind.mostWins, [(a, 1, 0), (b, 3, 1), (c, 1, 0), (d, 3, 0)]);
    expect(
      [for (final p in stat.players) (p.player.name, p.value, p.place, p.first)],
      [('B', 3, 1, true), ('D', 3, 1, true), ('A', 1, 3, false), ('C', 1, 3, false)],
    );
    final none = PlayerStat.rank(PlayerStatKind.busyStreak, [(a, 0, 0), (b, 0, 0)]);
    expect(none.players.where((p) => p.first), isEmpty, reason: 'a first place of 0 wins nothing');
  });

  testWidgets("this week's categories rank every player, boosts kept secret", (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await launchedGame(launchDate: firstMonday);
    await controller.advanceDay();

    await tester.pumpWidget(MaterialApp(home: PlayerStatsScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.textContaining('Days 1 to 2, so far.'), findsOneWidget);
    expect(find.textContaining('wins a trophy worth 3 ★'), findsOneWidget);
    final week = (await controller.playerStats(StatPeriod.week))!;
    final wins = week.stats.firstWhere((s) => s.kind == PlayerStatKind.mostWins);
    expect(find.text(PlayerStatKind.mostWins.description), findsOneWidget);
    for (final placed in wins.players) {
      expect(find.text(placed.player.isYou ? '${placed.player.name} (you)' : placed.player.name), findsOneWidget);
    }
    expect(find.text('${wins.players.first.value} wins'), findsWidgets);

    // Boosts are secret this week.
    await tester.tap(find.text('Most boosted'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Secret until the week is over'), findsOneWidget);
    expect(find.textContaining(' ★'), findsOneWidget, reason: 'only in the trophy line, no values');

    await tester.tap(find.text('Busy streak'));
    await tester.pumpAndSettle();
    expect(find.text(PlayerStatKind.busyStreak.description), findsOneWidget);

    // No last week yet.
    await tester.tap(find.text('Last week'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No finished week yet'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
  });

  testWidgets("last week's first places won trophies, and every player's trophies show", (tester) async {
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
    expect(find.text('Days 1 to 7. The first place of each category won a trophy worth 3 ★.'), findsOneWidget);
    await tester.tap(find.text('Most boosted'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Secret'), findsNothing, reason: 'not once the week is over');
    final last = (await controller.playerStats(StatPeriod.lastWeek))!;
    final boosted = last.stats.firstWhere((s) => s.kind == PlayerStatKind.mostBoosted);
    final firsts = boosted.players.where((p) => p.first);
    expect(find.text('+3 ★'), findsNWidgets(firsts.length));
    expect(find.byIcon(Icons.emoji_events_rounded), findsNWidgets(firsts.length));
    final withTrophies = boosted.players.where((p) => p.trophies > 0);
    expect(find.byIcon(Icons.emoji_events_outlined), findsNWidgets(withTrophies.length));
    for (final placed in withTrophies) {
      expect(find.text('×${placed.trophies}'), findsWidgets);
    }
    expect(tester.takeException(), isNull, reason: 'fits a phone');
  });
}
