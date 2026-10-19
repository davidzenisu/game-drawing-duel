import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/upgrades.dart';
import 'package:frontend/game/screens/results_screen.dart';

const _doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

CharacterCard _card(String id, Rarity rarity) => CharacterCard(
  id: id,
  subject: 'Sam $id',
  title: 'Title',
  rarity: rarity,
  prompt: 'Prompt',
  artist: 'Alex',
  sketch: _doodle,
);

/// Two adventurers (4 ★) against a challenger: they win without boosts.
FightSetup _fight({int boosts = 0}) => FightSetup(
  id: 'fight-$boosts',
  owner: const Player(id: 'p', name: 'Pat', isYou: true),
  challenger: _card('c', Rarity.basic),
  fighters: [
    FighterEntry(card: _card('a', Rarity.adventurer), element: ElementKind.fire),
    FighterEntry(card: _card('b', Rarity.adventurer)),
  ],
  day: 2,
  boosts: boosts,
);

Future<void> _open(WidgetTester tester, FightSetup fight) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: FightReplayScreen(fight: fight)));
}

void main() {
  testWidgets('the fighters enter, knock the challenger out and the stars reveal the winner', (tester) async {
    final fight = _fight();
    await _open(tester, fight);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Fight!'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the stage fits a phone');

    var waited = Duration.zero;
    while (find.text('K.O.!').evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 50));
      waited += const Duration(milliseconds: 50);
      expect(waited, lessThan(const Duration(seconds: 20)), reason: 'the fight ends');
    }
    expect(find.text('Fight!'), findsNothing);
    expect(find.text('The fighters win!'), findsNothing, reason: 'not before the fight ends');

    // The last blow plays out, then the stars count up.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.byType(FightOutcome), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('${fight.fighterStars} ★'), findsNothing, reason: 'still counting');
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('The fighters win!'), findsOneWidget);
    expect(find.text('${fight.fighterStars} ★'), findsOneWidget);
    expect(find.text('${fight.challengerStars} ★'), findsOneWidget);
    expect(find.text('No boosts'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the reveal fits a phone');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('skip goes straight to the reveal, and a tap shows it all', (tester) async {
    // Two boosts: 3 + 3 stars beat the fighters' 4.
    final fight = _fight(boosts: 2);
    await _open(tester, fight);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Skip'), findsNothing);

    await tester.tap(find.byType(FightOutcome));
    await tester.pump();
    expect(find.text('${fight.challenger.subject} wins!'), findsOneWidget);
    expect(find.text('3 + 3 from 2 boosts'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });
}
