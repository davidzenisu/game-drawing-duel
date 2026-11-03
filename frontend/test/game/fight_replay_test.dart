import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/upgrades.dart';
import 'package:frontend/game/screens/fight_replay_screen.dart';

import '../helpers.dart';

CharacterCard _card(String id, Rarity rarity) => CharacterCard(
  id: id,
  subject: 'Sam $id',
  title: 'Title',
  rarity: rarity,
  prompt: 'Prompt',
  artist: 'Alex',
  sketch: doodle,
);

/// Two adventurers (4 ★) against a challenger: they win without boosts.
FightSetup _fight({int boostStars = 0, List<int> fighterExtraStars = const [0, 0], int challengerExtraStars = 0}) =>
    FightSetup(
      id: 'fight-$boostStars',
      owner: const Player(id: 'p', name: 'Pat', isYou: true),
      challenger: _card('c', Rarity.basic),
      fighters: [
        FighterEntry(card: _card('a', Rarity.adventurer), element: ElementKind.fire, extraStars: fighterExtraStars[0]),
        FighterEntry(card: _card('b', Rarity.adventurer), extraStars: fighterExtraStars[1]),
      ],
      day: 4,
      boostStars: boostStars,
      challengerExtraStars: challengerExtraStars,
    );

Future<void> _open(WidgetTester tester, FightSetup fight, {int? rewardPulls}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: FightReplayScreen(fight: fight, rewardPulls: rewardPulls),
    ),
  );
}

Future<void> _skipToReveal(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Skip'));
  await tester.pump();
  await tester.pump();
  await tester.tap(find.byType(FightOutcome));
  await tester.pump();
}

void main() {
  testWidgets('the fighters enter, knock the challenger out and the stars reveal the winner', (tester) async {
    final fight = _fight();
    await _open(tester, fight);
    // The challenger drops in, then the fighters rise one by one.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Fight!'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1700));
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
    // Three boost stars: 3 + 3 stars beat the fighters' 4.
    final fight = _fight(boostStars: 3);
    await _open(tester, fight);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Skip'), findsNothing);

    await tester.tap(find.byType(FightOutcome));
    await tester.pump();
    expect(find.text('${fight.challenger.subject} wins!'), findsOneWidget);
    expect(find.text('3 + 3 from boosts'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the reveal counts both sides\' win rate extra stars', (tester) async {
    // 4 + 2 extra against 3 + 2 boosts + 1 extra: a tie.
    final fight = _fight(boostStars: 2, fighterExtraStars: [2, 0], challengerExtraStars: 1);
    expect((fight.fighterTotal, fight.challengerTotal, fight.fightersWin), (6, 6, false));
    await _open(tester, fight);
    await _skipToReveal(tester);
    await tester.pumpAndSettle();
    expect(find.text('6 ★'), findsNWidgets(2));
    expect(find.text('2 fighters · +2 from win rates'), findsOneWidget);
    expect(find.text('3 + 2 from boosts · +1 from win rates'), findsOneWidget);
    expect(find.text('Ties go to the challenger.'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
  });

  testWidgets('right after locking in, a win shows what it earned', (tester) async {
    final win = _fight();
    await _open(tester, win, rewardPulls: 1);
    await _skipToReveal(tester);
    expect(find.text('The fighters win!'), findsOneWidget);
    expect(find.text('+1 pull · +${win.challengerStars} victory ★'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    await tester.pumpWidget(const SizedBox());

    // In speed mode, a pull per challenger star.
    await _open(tester, win, rewardPulls: win.challengerStars);
    await _skipToReveal(tester);
    expect(find.text('+${win.challengerStars} pulls · +${win.challengerStars} victory ★'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    // A loss earns nothing, and replays never show it again.
    await _open(tester, _fight(boostStars: 3), rewardPulls: 1);
    await _skipToReveal(tester);
    expect(find.textContaining('victory ★'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _open(tester, win);
    await _skipToReveal(tester);
    expect(find.textContaining('victory ★'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
