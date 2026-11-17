import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/upgrades.dart';
import 'package:frontend/game/screens/pull_reveal_screen.dart';
import 'package:frontend/game/widgets/card_art.dart';
import 'package:frontend/game/widgets/gacha_box.dart';

import '../helpers.dart';

PullOutcome _outcome(String subject, Rarity rarity, {bool isNew = true}) => PullOutcome(
  card: CharacterCard(
    id: subject,
    subject: subject,
    title: 'Title',
    rarity: rarity,
    prompt: 'Prompt',
    artist: 'Alex',
    sketch: doodle,
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
Future<ValueNotifier<bool>> _open(
  WidgetTester tester,
  List<PullOutcome> outcomes, {
  Map<String, OwnedCard> owned = const {},
  GachaBanner banner = GachaBanner.standard,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final closed = ValueNotifier(false);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PullRevealScreen(outcomes: outcomes, owned: owned, banner: banner),
              ),
            );
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

GachaBox _theBox(WidgetTester tester) => tester.widget<GachaBox>(find.byType(GachaBox).first);

/// Swipes [by] to the right across the middle of the screen, cutting the
/// tape that far.
Future<void> _swipe(WidgetTester tester, {double by = 360}) async {
  final gesture = await tester.startGesture(const Offset(20, 420));
  for (var moved = 0.0; moved < by; moved += 20) {
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

/// The haptic feedback asked of the phone.
List<String> _buzzes(WidgetTester tester) {
  final buzzes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method.startsWith('HapticFeedback')) buzzes.add('${call.method} ${call.arguments ?? ''}'.trim());
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return buzzes;
}

void main() {
  testWidgets('a single pull: you cut the tape open, its rarity peeks out, then it comes out, flips and bursts', (
    tester,
  ) async {
    final buzzes = _buzzes(tester);
    final closed = await _open(tester, [_outcome('Sam', Rarity.legend)]);
    final boxes = tester.widgetList<GachaBox>(find.byType(GachaBox));
    expect(boxes.map((b) => b.layer), [GachaBoxLayer.back, GachaBoxLayer.front]);
    expect(find.text('Swipe along the tape to cut it open'), findsOneWidget);
    expect((_theBox(tester).cut, _theBox(tester).leak), (0, 0));

    // It waits for the cut: taps don't skip it.
    await tester.tapAt(const Offset(200, 420));
    await _wait(tester, const Duration(seconds: 3));
    expect(_theBox(tester).cut, 0);
    expect(find.byType(CardBack), findsNothing);

    // Half way, white light shines out of the cut, the phone buzzing.
    await _swipe(tester, by: 160);
    final box = _theBox(tester);
    expect(box.cut, inInclusiveRange(0.3, 0.7));
    expect((box.open, box.glow), (0, Colors.white), reason: "the legend's colour only comes at the end");
    expect(box.leak, box.cut, reason: 'the further the cut, the brighter');
    expect(buzzes.first, 'HapticFeedback.vibrate HapticFeedbackType.heavyImpact');
    expect(buzzes.where((b) => b == 'HapticFeedback.vibrate'), isNotEmpty, reason: 'buzzing as it cuts');

    // Through: the legend's colour shines out; it shakes, shut, leaking
    // light through its seams.
    await _swipe(tester);
    expect((_theBox(tester).cut, _theBox(tester).glow), (1, Rarity.legend.color));
    expect(find.text('Tap to skip'), findsOneWidget);
    await _wait(tester, const Duration(milliseconds: 1000));
    expect((_theBox(tester).open, _theBox(tester).leak), (0, 1));
    expect(find.byType(CardBack), findsNothing, reason: 'the card is still in the box');
    final cutBuzzes = buzzes.length;

    // Then it opens with one heavy buzz, and the card comes out.
    await _wait(tester, const Duration(milliseconds: 1200));
    expect(_theBox(tester).open, greaterThan(0));
    expect(buzzes.skip(cutBuzzes), ['HapticFeedback.vibrate HapticFeedbackType.heavyImpact']);
    expect(find.byType(CardBack), findsOneWidget);
    expect(find.text('Sam'), findsNothing);
    await _wait(tester, const Duration(seconds: 3));
    expect(find.byType(GachaBox), findsNothing, reason: 'gone once the card is out');
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

  test('a box opens with a longer, heavier buzz the rarer its best pull', () {
    final buzzes = [for (final rarity in Rarity.values) openingBuzzFor(rarity)];
    expect(buzzes, orderedEquals([...buzzes]..sort()));
    expect(buzzes.toSet(), hasLength(Rarity.values.length));
  });

  testWidgets("the weekly rate-up's box is taped in gold", (tester) async {
    await _open(tester, [_outcome('Sam', Rarity.hero)], banner: GachaBanner.weekly);
    final box = _theBox(tester);
    expect((box.tape, box.label), (Rarity.legend.color, 'WEEKLY HERO'));
    await tester.pumpWidget(const SizedBox());

    await _open(tester, [_outcome('Sam', Rarity.hero)]);
    expect(tester.widget<GachaBox>(find.byType(GachaBox).first).tape, GachaBox.plainTape);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('skip shows a single pull straight away, and so does a tap once the tape is cut', (tester) async {
    await _open(tester, [_outcome('Kim', Rarity.basic, isNew: false)]);
    final buzzes = _buzzes(tester);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.text('Kim'), findsOneWidget);
    expect(find.text('Duplicate · +1 upgrade point (×2)'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    expect(buzzes, isEmpty, reason: 'no buzz when skipped');
    await tester.pumpWidget(const SizedBox());

    await _open(tester, [_outcome('Kim', Rarity.basic, isNew: false)]);
    await _swipe(tester);
    await tester.tap(find.text('Tap to skip'));
    await tester.pump();
    expect(find.text('Kim'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a multi-pull shows the rarities in a carousel, then reveals each card on its own', (tester) async {
    final outcomes = [
      _outcome('Basic 0', Rarity.basic),
      _outcome('Robin', Rarity.hero),
      for (var i = 1; i < 8; i++) _outcome('Basic $i', Rarity.basic),
      _outcome('Kim', Rarity.legend, isNew: false),
    ];
    final closed = await _open(tester, outcomes);
    expect(find.text('10 pulls'), findsOneWidget);

    // One box for them all, its tape cut once, the rarest one's colour
    // peeking out.
    expect(find.text('Swipe along the tape to cut it open'), findsOneWidget);
    await _swipe(tester, by: 160);
    expect(_theBox(tester).glow, Colors.white);
    expect(find.byType(CardBack), findsNothing);
    await _swipe(tester);
    expect(_theBox(tester).glow, Rarity.legend.color);
    expect(find.text('Tap to hurry'), findsOneWidget);

    // The cards come out of the box, then the carousel only glows; no
    // characters yet.
    await _wait(tester, const Duration(milliseconds: 600));
    expect(find.byType(GachaBox), findsNWidgets(2));
    expect(find.byType(CardBack), findsWidgets);
    await _wait(tester, const Duration(seconds: 3));
    expect(find.byType(GachaBox), findsNothing, reason: 'it sinks away once empty');
    expect(tester.takeException(), isNull, reason: 'the carousel fits a phone');
    for (final outcome in outcomes) {
      expect(find.text(outcome.card.subject), findsNothing, reason: 'no characters in the carousel');
    }

    // Then every card gets a reveal of its own, in order, without a box
    // of its own.
    for (final (i, outcome) in outcomes.indexed) {
      await _until(tester, find.text('Tap to continue'));
      expect(find.byType(GachaBox), findsNothing);
      expect(find.text('${i + 1} / 10'), findsOneWidget);
      expect(find.text(outcome.card.subject), findsOneWidget);
      if (outcome.card.subject == 'Kim') expect(find.text('Duplicate · +1 upgrade point (×2)'), findsOneWidget);
      await tester.tap(find.text('Tap to continue'));
      await tester.pump();
    }
    await _until(tester, find.text('Your pulls'));
    expect(find.text('Tap to continue'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'the results fit a phone');

    // Once they've popped in, tapping a card shows it again, without a
    // counter.
    await _wait(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Basic 3'));
    await tester.pump();
    await _until(tester, find.text('Tap to continue'));
    expect(find.text('5 / 10'), findsNothing);
    await tester.tap(find.text('Tap to continue'));
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pump();
    await _wait(tester, const Duration(milliseconds: 400));
    expect(closed.value, isTrue);
  });

  testWidgets('a tap hurries the carousel, and skip in a reveal skips the rest', (tester) async {
    await _open(tester, [for (var i = 0; i < 10; i++) _outcome('Basic $i', Rarity.basic)]);
    await _swipe(tester);
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    await tester.pump();
    expect(find.text('1 / 10'), findsOneWidget);

    await tester.tap(find.text('Skip').last);
    await tester.pump();
    await tester.pump();
    expect(find.text('Your pulls'), findsOneWidget);
    expect(find.text('1 / 10'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('skip in the carousel goes straight to the results', (tester) async {
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

  testWidgets('a duplicate shows plain, and tells whether its next upgrade is ready', (tester) async {
    final kim = _outcome('Kim', Rarity.basic, isNew: false);
    final sam = _outcome('Sam', Rarity.basic, isNew: false);
    final upgraded = OwnedCard(kim.card)
      ..copies = 2
      ..unlocked.add(UpgradeEffect.shadow);
    final ready = OwnedCard(sam.card)..copies = 10;
    await _open(tester, [kim], owned: {'Kim': upgraded, 'Sam': ready});
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(tester.widget<Standee>(find.byType(Standee)).effects, isEmpty, reason: 'the drawing stays the focus');
    expect(find.text('Upgrade ready!'), findsNothing, reason: 'its next upgrade costs more');
    await tester.pumpWidget(const SizedBox());

    // In the overview of several pulls too.
    await _open(
      tester,
      [for (var i = 0; i < 8; i++) _outcome('Basic $i', Rarity.basic), kim, sam],
      owned: {'Kim': upgraded, 'Sam': ready},
    );
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();
    for (final standee in tester.widgetList<Standee>(find.byType(Standee))) {
      expect(standee.effects, isEmpty, reason: standee.card.subject);
    }
    expect(find.text('Upgrade ready!'), findsOneWidget, reason: "Sam's next upgrade is paid for");
    await tester.pumpWidget(const SizedBox());
  });
}
