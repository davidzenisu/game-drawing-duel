import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/screens/prompt_screen.dart';
import 'package:frontend/game/widgets/card_art.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';

import '../helpers.dart';

void main() {
  testWidgets('picking a player shows no drawing of them', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame(launchDate: firstMonday);
    await tester.pumpWidget(MaterialApp(home: PromptScreen(controller: game)));
    await tester.pump();
    for (final player in game.promptCandidates) {
      await tester.tap(find.widgetWithText(ChoiceChip, player.name));
      await tester.pump();
      expect(find.byType(Standee), findsNothing, reason: player.name);
      expect(find.byType(SketchView), findsNothing, reason: player.name);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the players picked least this week show the star more they earn', (tester) async {
    final game = await launchedGame(launchDate: firstMonday);
    while (game.leastPicked.isEmpty) {
      await game.advanceDay();
    }
    await tester.pumpWidget(MaterialApp(home: PromptScreen(controller: game)));
    await tester.pump();
    expect(find.text('+${StarRewards.leastPicked}'), findsNWidgets(game.leastPicked.length));
    for (final player in game.leastPicked) {
      expect(find.bySemanticsLabel('${player.name}, ${StarRewards.leastPicked} star more'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
