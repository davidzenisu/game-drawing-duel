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
    // The shadow and the outline cost 1 + 2; one duplicate is left.
    final owned = game.collection.firstWhere((o) => o.card.rarity == Rarity.basic)
      ..copies = 5
      ..unlocked.addAll([UpgradeEffect.shadow, UpgradeEffect.outline]);
    expect(owned.costs, [1, 2, 3, 5, 7, 10]);
    expect(owned.nextUpgrade, UpgradeEffect.light);

    await tester.pumpWidget(
      MaterialApp(
        home: CharacterDetailScreen(controller: game, owned: owned),
      ),
    );
    // The effects keep animating, so the screen never settles.
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.text('1 duplicate'), findsOneWidget);
    expect(find.textContaining('28 to unlock them all'), findsOneWidget);
    for (final cost in [3, 5, 7, 10]) {
      expect(find.text('$cost ×'), findsOneWidget, reason: 'the locked steps show their cost');
    }
    expect(find.text('1/3 duplicates'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, closeTo(1 / 3, 1e-9));
    // The mockup unlocks on credit.
    expect(find.text('Unlock on credit (3)'), findsOneWidget);

    owned.copies = 7;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: CharacterDetailScreen(controller: game, owned: owned),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Unlock (3 duplicates)'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('upgrades unlocked before a path grew keep their place', () {
    final card = CharacterCard(
      id: 'c',
      subject: 'S',
      title: 'T',
      rarity: Rarity.basic,
      prompt: 'Basic',
      artist: 'A',
      sketch: Sketch.empty,
    );
    // Basics used to unlock the light right after the shadow.
    final owned = OwnedCard(card)
      ..copies = 6
      ..unlocked.addAll([UpgradeEffect.shadow, UpgradeEffect.light]);
    expect(owned.nextUpgrade, UpgradeEffect.outline);
    expect(owned.upgradePoints, 6 - 1 - (1 + 3));
    expect(owned.nextUpgradeCost, 2);
    expect(owned.canUpgrade(), isFalse);
  });
}
