import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/challengers_screen.dart';

import '../helpers.dart';

void main() {
  testWidgets('your challenger that won has a button to collect its stars', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Day 2's challenger won its fight on day 4.
    final game = await launchedGame(day: 2);
    await game.submitChallenger(doodle);
    for (var i = 0; i < 3; i++) {
      await game.advanceDay();
    }
    final stars = game.challengers.firstWhere((r) => r.card.day == 2).starsToCollect;
    await tester.pumpWidget(MaterialApp(home: ChallengersScreen(controller: game)));
    await tester.pump();
    final before = game.stars;

    await tester.tap(find.text('Collect $stars'));
    await tester.pump();
    expect(game.stars, before + stars);
    expect(find.text('Collect $stars'), findsNothing);
    expect(find.text('$stars collected'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits its tile');
    await tester.pumpWidget(const SizedBox());
  });
}
