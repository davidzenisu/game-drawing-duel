import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/upgrades.dart';
import 'package:frontend/game/screens/collection_screen.dart';

import '../mockup/mock_game_session_test.dart' show launchedGame;

void main() {
  testWidgets('each upgrade shows its cost, and the next one how far along it is', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame();
    final owned = game.collection.firstWhere((o) => o.card.rarity == Rarity.basic)..copies = 4;
    expect(owned.costs, UpgradeTree.costsFor(Rarity.basic));

    await tester.pumpWidget(
      MaterialApp(
        home: CharacterDetailScreen(controller: game, owned: owned),
      ),
    );
    // The effects keep animating, so the screen never settles.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('3 duplicates'), findsOneWidget);
    expect(find.textContaining('30 to unlock them all'), findsOneWidget);
    for (final cost in owned.costs) {
      expect(find.text('$cost ×'), findsOneWidget);
    }
    expect(find.text('3/10 duplicates'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, closeTo(0.3, 1e-9));
    // The mockup unlocks on credit.
    expect(find.text('Unlock on credit (10)'), findsOneWidget);

    owned.copies = 11;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: CharacterDetailScreen(controller: game, owned: owned),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Unlock (10 duplicates)'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
