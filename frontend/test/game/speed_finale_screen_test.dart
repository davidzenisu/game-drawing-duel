import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/screens/speed_finale_screen.dart';

import '../helpers.dart';

void main() {
  testWidgets('the winner comes first with its stars, then the others scroll by', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await launchedGame(
      others: ['Alex', 'Sam', 'Robin', 'Kim'],
      launchDate: firstMonday,
      speed: true,
    );
    for (var day = 1; day <= SpeedMode.days.length; day++) {
      await controller.advanceDay();
    }
    final ranking = (await controller.weekRanking())!;
    expect(ranking.challengers.length, greaterThan(3));
    final winner = ranking.challengers.first;

    await tester.pumpWidget(MaterialApp(home: SpeedFinaleScreen(controller: controller)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('The winner'), findsOneWidget);
    expect(find.text(winner.card.title), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('${winner.stars} ★'), findsOneWidget, reason: 'counted up');
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('${ranking.challengers[1].stars} ★'), findsWidgets);

    // After the winner's moment, the others scroll by on their own.
    final strip = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(strip.offset, 0);
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(seconds: 2));
    expect(strip.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the hub opens the final ranking when the session ends', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await launchedGame(
      others: ['Alex', 'Sam', 'Robin', 'Kim'],
      launchDate: firstMonday,
      speed: true,
    );
    for (var day = 1; day < SpeedMode.days.length; day++) {
      await controller.advanceDay();
    }
    for (final key in ['welcome']) {
      await controller.markTutorialSeen(key);
    }
    await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: controller)));
    await tester.pump(const Duration(seconds: 1));
    // The launch bonus greets first.
    final greeting = find.text("Let's go");
    if (greeting.evaluate().isNotEmpty) {
      await tester.tap(greeting);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(controller.day, SpeedMode.days.length);
    await tester.tap(find.text('Next day'));
    await tester.pump(const Duration(milliseconds: 300));
    // Confirms skipping the steps still open today.
    final confirm = find.widgetWithText(FilledButton, 'Next day');
    if (confirm.evaluate().isNotEmpty) await tester.tap(confirm);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(controller.sessionOver, isTrue);
    expect(find.byType(SpeedFinaleScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
