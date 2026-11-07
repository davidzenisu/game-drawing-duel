import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/win_rates_screen.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';

import '../helpers.dart';

void main() {
  testWidgets("every player opens their matchups that change stars", (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await launchedGame(launchDate: firstMonday, day: 8);
    final rates = (await controller.winRates())!;

    await tester.pumpWidget(MaterialApp(home: WinRatesScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.textContaining('From the fights of days 1 to 7'), findsOneWidget);
    // Every player is a card with their basic drawing as the preview.
    final players = controller.server.players;
    expect(find.widgetWithText(FilledButton, 'Win rates'), findsNWidgets(players.length));
    for (final player in players) {
      expect(basicDrawingOf(controller, player), isNotNull, reason: player.name);
    }
    expect(find.byType(SketchView), findsNWidgets(players.length));

    // A player with extra stars: their matchups, theirs on the left.
    final best = rates.rates.reduce((a, b) => b.extraStars > a.extraStars ? b : a);
    expect(best.extraStars, greaterThan(0));
    final index = players.indexWhere((p) => p.name == best.player.name);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Win rates').at(index));
    await tester.tap(find.widgetWithText(FilledButton, 'Win rates').at(index));
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
    // The two sides of a matchup are the same size, extra stars or not.
    for (final vs in find.text('vs').evaluate()) {
      final row = find.ancestor(of: find.byWidget(vs.widget), matching: find.byType(Row)).first;
      final sides = find.descendant(of: row, matching: find.byType(Card));
      expect(tester.getSize(sides.at(0)), tester.getSize(sides.at(1)));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a player without star changes has no matchups', (tester) async {
    final controller = await launchedGame(launchDate: firstMonday);
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
