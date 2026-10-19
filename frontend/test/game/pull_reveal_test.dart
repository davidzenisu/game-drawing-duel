import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/pull_reveal_screen.dart';

const _doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

PullOutcome _outcome(String subject, Rarity rarity, {bool isNew = true}) => PullOutcome(
  card: CharacterCard(
    id: subject,
    subject: subject,
    title: 'Title',
    rarity: rarity,
    prompt: 'Prompt',
    artist: 'Alex',
    sketch: _doodle,
  ),
  isNew: isNew,
  copies: isNew ? 1 : 2,
);

/// Lets [time] pass frame by frame, so chained animations follow each other.
Future<void> _wait(WidgetTester tester, Duration time) async {
  for (var passed = Duration.zero; passed < time; passed += const Duration(milliseconds: 50)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the reveal from a button, and tells whether it closed again.
Future<ValueNotifier<bool>> _open(WidgetTester tester, List<PullOutcome> outcomes) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final closed = ValueNotifier(false);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            await Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => PullRevealScreen(outcomes: outcomes)));
            closed.value = true;
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return closed;
}

void main() {
  testWidgets('a single pull builds up longer the rarer it is, then flips and bursts', (tester) async {
    final closed = await _open(tester, [_outcome('Sam', Rarity.legend)]);
    // A legend builds up for 2 seconds; nothing shows before that.
    await _wait(tester, const Duration(milliseconds: 1400));
    expect(find.text('Sam'), findsNothing);
    expect(find.text('Tap to skip'), findsOneWidget);

    await _wait(tester, const Duration(seconds: 1));
    await _wait(tester, const Duration(seconds: 2));
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('New character!'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(Rarity.legend.stars));
    expect(find.text('Tap to continue'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    await tester.tap(find.text('Tap to continue'));
    await tester.pump();
    await _wait(tester, const Duration(milliseconds: 400));
    expect(closed.value, isTrue);
  });

  testWidgets('a tap shows a single pull straight away', (tester) async {
    await _open(tester, [_outcome('Kim', Rarity.basic, isNew: false)]);
    await tester.tap(find.text('Tap to skip'));
    await tester.pump();
    expect(find.text('Kim'), findsOneWidget);
    expect(find.text('Duplicate · +1 upgrade point (×2)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a multi-pull deals and flips the cards, then spotlights the rare ones', (tester) async {
    final outcomes = [
      for (var i = 0; i < 8; i++) _outcome('Basic $i', Rarity.basic),
      _outcome('Hero', Rarity.hero),
      _outcome('Legend', Rarity.legend, isNew: false),
    ];
    final closed = await _open(tester, outcomes);
    expect(find.text('10 pulls'), findsOneWidget);

    // Built up, dealt and flipped one after another.
    await _wait(tester, const Duration(seconds: 2));
    expect(find.text('Your pulls'), findsNothing, reason: 'still building up');
    await _wait(tester, const Duration(seconds: 5));
    expect(find.text('Your pulls'), findsOneWidget);
    expect(find.text('Basic 0'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the cards fit a phone');

    // The hero, then the legend, get a reveal of their own.
    await _wait(tester, const Duration(seconds: 2));
    expect(find.text('New character!'), findsOneWidget);
    await tester.tap(find.text('Tap to continue'));
    await tester.pump();
    await _wait(tester, const Duration(seconds: 3));
    expect(find.text('Duplicate · +1 upgrade point (×2)'), findsOneWidget);
    await tester.tap(find.text('Tap to continue'));
    await tester.pump();
    expect(find.text('Tap to continue'), findsNothing);

    // Tapping a card shows it again.
    await tester.tap(find.text('Basic 3'));
    await tester.pump();
    await _wait(tester, const Duration(seconds: 3));
    await tester.tap(find.text('Tap to continue'));
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pump();
    await _wait(tester, const Duration(milliseconds: 400));
    expect(closed.value, isTrue);
  });

  testWidgets('skip goes straight to the results, without spotlights', (tester) async {
    await _open(tester, [
      for (var i = 0; i < 9; i++) _outcome('Basic $i', Rarity.basic),
      _outcome('Hero', Rarity.hero),
    ]);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Your pulls'), findsOneWidget);
    expect(find.text('Hero'), findsOneWidget);
    expect(find.text('Tap to continue'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
