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

/// Lets frames pass until [finder] finds something.
Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 400 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
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

  testWidgets('a multi-pull turns its cards past twice: rarities first, then characters', (tester) async {
    final outcomes = [
      _outcome('Basic 0', Rarity.basic),
      _outcome('Robin', Rarity.hero),
      for (var i = 1; i < 8; i++) _outcome('Basic $i', Rarity.basic),
      _outcome('Kim', Rarity.legend, isNew: false),
    ];
    final closed = await _open(tester, outcomes);
    expect(find.text('10 pulls'), findsOneWidget);

    // Built up to the legend, then each card shows only its rarity.
    await _wait(tester, const Duration(milliseconds: 2200));
    expect(find.text('Rarities · 1/10'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the carousel fits a phone');
    final rarities = <String>{};
    while (find.text('Reveal · 1/10').evaluate().isEmpty) {
      for (final rarity in Rarity.values) {
        if (find.text(rarity.label).evaluate().isNotEmpty) rarities.add(rarity.label);
      }
      for (final outcome in outcomes) {
        expect(find.text(outcome.card.subject), findsNothing, reason: 'no characters before the reveal');
      }
      await _wait(tester, const Duration(milliseconds: 100));
      expect(rarities.length, lessThan(5), reason: 'the preview ends');
    }
    expect(rarities, {Rarity.basic.label, Rarity.hero.label, Rarity.legend.label});

    // Then each one flips; the hero and the legend get a reveal of their own.
    await _until(tester, find.text('Basic 0'));
    await _until(tester, find.text('Tap to continue'));
    expect(find.text('New character!'), findsOneWidget);
    expect(find.text('Robin'), findsWidgets);
    await tester.tap(find.text('Tap to continue'));
    await tester.pump();
    await _until(tester, find.text('Tap to continue'));
    expect(find.text('Duplicate · +1 upgrade point (×2)'), findsOneWidget);
    await tester.tap(find.text('Tap to continue'));
    await tester.pump();
    await _until(tester, find.text('Your pulls'));
    expect(find.text('Tap to continue'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'the results fit a phone');

    // Once they've popped in, tapping a card shows it again.
    await _wait(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Basic 3'));
    await tester.pump();
    await _until(tester, find.text('Tap to continue'));
    await tester.tap(find.text('Tap to continue'));
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pump();
    await _wait(tester, const Duration(milliseconds: 400));
    expect(closed.value, isTrue);
  });

  testWidgets('a tap hurries the current card along', (tester) async {
    await _open(tester, [for (var i = 0; i < 10; i++) _outcome('Basic $i', Rarity.basic)]);
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    await tester.pump();
    expect(find.text('Rarities · 1/10'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    await tester.pump();
    expect(find.text('Rarities · 2/10'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
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
