import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/upgrades.dart';
import 'package:frontend/game/screens/collection_screen.dart';
import 'package:frontend/game/screens/progress_screen.dart';
import 'package:frontend/game/widgets/card_art.dart';

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

  testWidgets('filters and sorts the collection', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame();
    final maxed = game.collection.firstWhere((o) => o.card.rarity == Rarity.basic);
    maxed
      ..copies = 40
      ..unlocked.addAll(maxed.path);
    final ready = game.collection.firstWhere((o) => o.card.rarity == Rarity.adventurer)..copies = 2;

    await tester.pumpWidget(MaterialApp(home: CollectionScreen(controller: game)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    Future<void> tap(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pump();
      await tester.tap(find.text(text));
      await tester.pump(const Duration(milliseconds: 500));
    }

    Iterable<String> shownIds() => tester.widgetList<Standee>(find.byType(Standee)).map((s) => s.card.id);
    await tap('Maxed out');
    expect(shownIds(), [maxed.card.id]);

    await tap('Upgrade ready');
    expect(shownIds(), contains(ready.card.id));
    expect(shownIds(), isNot(contains(maxed.card.id)));

    await tap('Not summoned');
    final standees = tester.widgetList<Standee>(find.byType(Standee));
    expect(standees, isNotEmpty);
    expect(standees.every((s) => s.hidden), isTrue);

    // Characters not summoned yet have no element.
    await tap('fire');
    expect(find.text('No characters match these filters.'), findsOneWidget);
    await tap('fire');
    await tap('Not summoned');

    await tester.tap(find.byTooltip('Sort'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(InkWell, 'Most copies').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(shownIds().first, maxed.card.id, reason: '40 copies');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unlocked effects can be switched off and on', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame();
    final owned = game.collection.firstWhere((o) => o.card.rarity == Rarity.basic)
      ..copies = 4
      ..unlocked.addAll([UpgradeEffect.shadow, UpgradeEffect.outline]);

    await tester.pumpWidget(
      MaterialApp(
        home: CharacterDetailScreen(controller: game, owned: owned),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Switch), findsNWidgets(2), reason: 'one per unlocked effect');
    Standee standee() => tester.widget<Standee>(find.byType(Standee));
    expect(standee().effects, [UpgradeEffect.shadow, UpgradeEffect.outline]);

    await tester.tap(find.byTooltip('Hide Outline'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(owned.hidden, {UpgradeEffect.outline});
    expect(standee().effects, [UpgradeEffect.shadow]);
    expect(owned.unlocked, contains(UpgradeEffect.outline), reason: 'still unlocked');

    await tester.tap(find.byTooltip('Show Outline'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(owned.hidden, isEmpty);
    expect(standee().effects, [UpgradeEffect.shadow, UpgradeEffect.outline]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the progress view sums up the collection', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame();
    final maxed = game.collection.firstWhere((o) => o.card.rarity == Rarity.basic);
    maxed
      ..copies = 1 + 28 + 2
      ..unlocked.addAll(maxed.path);

    await tester.pumpWidget(MaterialApp(home: CollectionScreen(controller: game)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Progress'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ProgressScreen), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    final owned = game.collection.length;
    expect(find.text('1/$owned'), findsOneWidget, reason: 'one maxed out');
    expect(find.text('$owned/${game.pool.length}'), findsOneWidget, reason: 'collected');
    final spare = find.ancestor(of: find.text('Spare duplicates'), matching: find.byType(Row));
    expect(find.descendant(of: spare, matching: find.text('2')), findsOneWidget);
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
