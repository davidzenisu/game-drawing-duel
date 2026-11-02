import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/win_rates_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

const _doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

Future<MockGameSession> _launched() async {
  // Day 1 is a Monday: the first week ends on day 7.
  final controller = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 10, 5, 12));
  await controller.signUp('Pat');
  await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
  while (!controller.server.everyoneJoined) {
    await controller.refreshServer();
  }
  await controller.startSetup();
  for (final assignment in controller.assignments) {
    await controller.submitSetupDrawing(assignment, _doodle, 'Title');
  }
  await controller.launch();
  return controller;
}

void main() {
  testWidgets("the win rates table shows last week's meetings and their extra stars", (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _launched();

    await tester.pumpWidget(MaterialApp(home: WinRatesScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.textContaining('nobody fought last week'), findsOneWidget);

    for (var day = 1; day < 8; day++) {
      await controller.advanceDay();
    }
    final rates = (await controller.winRates())!;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: WinRatesScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.text('From the fights of days 1 to 7'), findsOneWidget);
    for (final header in ['Player', 'Against', 'Won', 'Extra']) {
      expect(find.text(header), findsOneWidget);
    }
    final best = rates.rates.reduce((a, b) => b.extraStars > a.extraStars ? b : a);
    expect(best.extraStars, greaterThan(0));
    expect(find.text('+${best.extraStars} ★'), findsWidgets);
    expect(find.text('${best.wins} / ${best.fights}'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
