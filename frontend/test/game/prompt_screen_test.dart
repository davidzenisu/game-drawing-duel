import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/prompt_screen.dart';
import 'package:frontend/game/widgets/card_art.dart';

import '../helpers.dart';

void main() {
  testWidgets("a picked player's preview is always their basic drawing", (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame(launchDate: firstMonday, numberedTitles: true);
    // Every player shows up in the pool with rarer drawings too.
    expect(
      game.promptCandidates.every((p) => game.pool.any((c) => c.subject == p.name && c.rarity != Rarity.basic)),
      isTrue,
    );
    await tester.pumpWidget(MaterialApp(home: PromptScreen(controller: game)));
    await tester.pump();
    for (final player in game.promptCandidates) {
      await tester.tap(find.widgetWithText(ChoiceChip, player.name));
      await tester.pump();
      final preview = tester.widget<Standee>(find.byType(Standee)).card;
      expect((preview.subject, preview.rarity, preview.day), (player.name, Rarity.basic, 0), reason: player.name);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
