import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/gacha_screen.dart';
import 'package:frontend/game/screens/pool_screen.dart';
import 'package:frontend/game/widgets/card_art.dart';
import 'package:frontend/mockup/mock_game_session.dart';

const _doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

Future<MockGameSession> _launched() async {
  final controller = MockGameSession(seed: 1);
  await controller.signUp('Pat');
  await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim']);
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
  testWidgets('summon shows what you can pull, by rarity and chance, on a phone', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _launched();
    final pool = controller.pool;
    final rates = GachaMachine.tierRates({for (final card in pool) card.rarity});
    final owned = {for (final o in controller.collection) o.card.id};

    await tester.pumpWidget(MaterialApp(home: GachaScreen(controller: controller)));
    await tester.pump();
    final open = find.text('See what you can pull');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(PoolScreen), findsOneWidget);
    expect(find.textContaining('${pool.length} characters.'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    // A section for every rarity in the pool, with its chance and count.
    for (final MapEntry(key: rarity, value: rate) in rates.entries) {
      final count = pool.where((card) => card.rarity == rarity).length;
      final section = find.ancestor(of: find.text(rarity.label), matching: find.byType(Card));
      await tester.ensureVisible(section);
      expect(
        find.descendant(of: section, matching: find.text('$rate%')),
        findsOneWidget,
        reason: rarity.label,
      );
      expect(
        find.descendant(of: section, matching: find.textContaining('$count character')),
        findsOneWidget,
        reason: rarity.label,
      );
      final summoned = pool.where((card) => card.rarity == rarity && owned.contains(card.id)).length;
      expect(find.descendant(of: section, matching: find.textContaining('$summoned/$count summoned')), findsOneWidget);
    }
    expect(rates.values.reduce((a, b) => a + b), 100);

    // Only the characters you own show their drawing.
    final standees = tester.widgetList<Standee>(find.byType(Standee));
    expect(standees, hasLength(pool.length));
    for (final standee in standees) {
      expect(standee.hidden, !owned.contains(standee.card.id), reason: standee.card.subject);
    }
    // Everyone's name shows, summoned or not.
    for (final card in pool) {
      expect(find.text(card.title), findsWidgets, reason: card.subject);
    }

    // A newly pulled character shows its drawing too.
    late CharacterCard pulled;
    do {
      pulled = (await controller.pull(1)).single.card;
    } while (owned.contains(pulled.id));
    await tester.pump();
    expect(
      tester.widget<Standee>(find.byWidgetPredicate((w) => w is Standee && w.card.id == pulled.id)).hidden,
      isFalse,
    );
    final count = pool.where((card) => card.rarity == pulled.rarity).length;
    final summoned = pool.where((card) => card.rarity == pulled.rarity && owned.contains(card.id)).length + 1;
    final section = find.ancestor(of: find.text(pulled.rarity.label), matching: find.byType(Card));
    expect(find.descendant(of: section, matching: find.textContaining('$summoned/$count summoned')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
