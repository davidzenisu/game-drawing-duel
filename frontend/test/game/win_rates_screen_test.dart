import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/win_rates_screen.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';
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
  testWidgets("every player opens their matchups that change stars", (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _launched();
    for (var day = 1; day < 8; day++) {
      await controller.advanceDay();
    }
    final rates = (await controller.winRates())!;

    await tester.pumpWidget(MaterialApp(home: WinRatesScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.textContaining('From the fights of days 1 to 7'), findsOneWidget);
    // Every player is a card with their basic drawing as the preview.
    final players = controller.server.players;
    expect(find.text('Show win rates'), findsNWidgets(players.length));
    for (final player in players) {
      expect(basicDrawingOf(controller, player), isNotNull, reason: player.name);
    }
    expect(find.byType(SketchView), findsNWidgets(players.length));

    // A player with extra stars: their matchups, theirs on the left.
    final best = rates.rates.reduce((a, b) => b.extraStars > a.extraStars ? b : a);
    expect(best.extraStars, greaterThan(0));
    final index = players.indexWhere((p) => p.name == best.player.name);
    await tester.ensureVisible(find.text('Show win rates').at(index));
    await tester.tap(find.text('Show win rates').at(index));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.byType(PlayerWinRatesScreen), findsOneWidget);
    expect(find.text('+${best.extraStars} ★'), findsWidgets);
    expect(find.text('won ${best.wins}/${best.fights} fights'), findsWidgets);
    expect(find.text('vs'), findsWidgets);

    // Only the matchups that change stars on either side.
    final changing = {
      for (final r in rates.rates)
        if (r.extraStars > 0 && (r.player.name == best.player.name || r.against.name == best.player.name))
          r.player.name == best.player.name ? r.against.name : r.player.name,
    };
    expect(find.text('vs'), findsNWidgets(changing.length));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a player without star changes has no matchups', (tester) async {
    final controller = await _launched();
    final rates = (await controller.winRates())!;
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerWinRatesScreen(controller: controller, player: controller.server.players.first, rates: rates),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No extra stars for or against'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
