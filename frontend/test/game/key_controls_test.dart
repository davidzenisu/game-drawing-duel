import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/boost_screen.dart';
import 'package:frontend/game/screens/gacha_screen.dart';
import 'package:frontend/game/screens/pull_reveal_screen.dart';
import 'package:frontend/game/tutorials.dart';
import 'package:frontend/game/widgets/gacha_box.dart';
import 'package:frontend/game/widgets/key_controls.dart';
import 'package:frontend/game/widgets/tutorial_dialog.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

void _screen(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Opens [screen] from a button, to go back from; [settle] false for a
/// screen that never stops moving, giving it time to come in.
Future<void> _push(WidgetTester tester, Widget screen, {bool settle = true}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  if (settle) {
    await tester.pumpAndSettle();
    return;
  }
  // The page slides in (and a summon's box lands).
  await _frames(tester, const Duration(milliseconds: 1250));
}

/// Lets [time] pass frame by frame, also on screens that never stop moving.
Future<void> _frames(WidgetTester tester, [Duration time = const Duration(milliseconds: 600)]) async {
  for (var passed = Duration.zero; passed < time; passed += const Duration(milliseconds: 50)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _frames(tester);
}

/// A mockup game on day 3, with three challengers to boost.
Future<MockGameSession> _boostDay() async {
  final controller = MockGameSession(seed: 1);
  await controller.signUp('Pat');
  await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim']);
  while (!controller.server.everyoneJoined) {
    await controller.refreshServer();
  }
  await controller.startSetup();
  for (final assignment in controller.assignments) {
    await controller.submitSetupDrawing(assignment, doodle, 'Title');
  }
  await controller.launch();
  await controller.submitPrompt('Sunburnt', controller.promptCandidates.first);
  await controller.advanceDay();
  await controller.submitChallenger(doodle);
  await controller.advanceDay();
  return controller;
}

PullOutcome _outcome(String subject, Rarity rarity) => PullOutcome(
  card: CharacterCard(
    id: subject,
    subject: subject,
    title: 'Title',
    rarity: rarity,
    prompt: 'Prompt',
    artist: 'Alex',
    sketch: doodle,
  ),
  isNew: true,
  copies: 1,
);

/// Lets frames pass until [finder] finds something.
Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 400 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

void main() {
  group('KeyControls', () {
    testWidgets('calls a callback per key, and leaves keys without one', (tester) async {
      final pressed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: KeyControls(
            onLeft: () => pressed.add('left'),
            onRight: () => pressed.add('right'),
            onUp: () => pressed.add('up'),
            onDown: () => pressed.add('down'),
            onConfirm: () => pressed.add('confirm'),
            child: const Scaffold(),
          ),
        ),
      );
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
      ]) {
        expect(await tester.sendKeyEvent(key), isTrue, reason: '$key');
      }
      expect(pressed, ['left', 'right', 'up', 'down', 'confirm', 'confirm']);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse, reason: 'no onBack');
    });

    testWidgets('leaves a text field its arrows, and a focused button its Enter', (tester) async {
      final pressed = <String>[];
      final field = TextEditingController(text: 'Sunburnt');
      addTearDown(field.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: KeyControls(
            onLeft: () => pressed.add('left'),
            onConfirm: () => pressed.add('confirm'),
            child: Scaffold(
              body: Column(
                children: [
                  TextField(controller: field),
                  TextButton(onPressed: () => pressed.add('button'), child: const Text('Button')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final end = field.selection.baseOffset;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(pressed, isEmpty);
      expect(field.selection.baseOffset, end - 1, reason: 'the cursor moved');

      // A button focused with Tab presses itself on Enter.
      FocusManager.instance.primaryFocus?.nextFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, ['button']);
    });
  });

  testWidgets('takes the keys again once a dialog opened over its screen right away is closed', (tester) async {
    final pressed = <String>[];
    await _push(
      tester,
      Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (pressed.isEmpty) {
              pressed.add('opened');
              showTutorial(context, Tutorial.welcome);
            }
          });
          return KeyControls(onRight: () => pressed.add('right'), child: const Scaffold());
        },
      ),
    );
    expect(find.byType(TutorialDialog), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(TutorialDialog), findsNothing);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(pressed, ['opened', 'right']);
  });

  testWidgets('tutorials: ← / → page, Enter goes on, Esc closes; big arrows on wide screens', (tester) async {
    _screen(tester, width: 1000);
    const tutorial = Tutorial.welcome;
    expect(tutorial.pages.length, greaterThanOrEqualTo(2));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(onPressed: () => showTutorial(context, tutorial), child: const Text('Open')),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final first = find.text(tutorial.pages[0].title);
    final second = find.text(tutorial.pages[1].title);
    expect(first, findsOneWidget);
    expect(find.byTooltip('Next page'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(first, findsOneWidget, reason: 'nothing before the first page');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(second, findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(first, findsOneWidget);
    await _press(tester, LogicalKeyboardKey.enter);
    expect(second, findsOneWidget, reason: 'Enter is Next');
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(first, findsOneWidget);

    // On to the last page, where Enter is "Got it".
    for (var page = 1; page < tutorial.pages.length; page++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(find.text('Got it'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('Got it'), findsOneWidget, reason: 'nothing after the last page');
    await _press(tester, LogicalKeyboardKey.space);
    expect(find.byType(TutorialDialog), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(TutorialDialog), findsNothing);
  });

  testWidgets('tutorials keep to swiping and Next on a phone', (tester) async {
    _screen(tester);
    await tester.pumpWidget(const MaterialApp(home: TutorialDialog(tutorial: Tutorial.welcome)));
    expect(find.byTooltip('Next page'), findsNothing);
  });

  testWidgets('boost: ← / → between challengers, ↑ / ↓ give and take stars, Esc asks before leaving', (tester) async {
    _screen(tester, width: 1000);
    final controller = await _boostDay();
    final targets = controller.boostTargets;
    await _push(tester, BoostScreen(controller: controller));
    expect(find.text('Boost challengers 1/${targets.length}'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text('Boost challengers 1/${targets.length}'), findsOneWidget, reason: 'nothing before the first');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('Boost challengers 2/${targets.length}'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.textContaining('1 of 3 left'), findsOneWidget);
    expect(find.byKey(ValueKey('${targets[1].challenger.id}-1')), findsOneWidget, reason: 'given to the one in view');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.textContaining('2 of 3 left'), findsOneWidget);

    for (var i = 0; i < targets.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(find.text('Boost challengers ${targets.length}/${targets.length}'), findsOneWidget);

    // Unsaved: Esc asks first.
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.text('Save your boosts?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(BoostScreen), findsNothing);
  });

  testWidgets('summon: ← / → switch banners, with big arrows on wide screens; Esc goes back', (tester) async {
    _screen(tester, width: 1000);
    final controller = await launchedGame(others: ['Alex', 'Sam', 'Robin', 'Kim']);
    await _push(tester, GachaScreen(controller: controller), settle: false);
    String caption() => tester
        .widget<Text>(
          find.textContaining('The same pool').evaluate().isEmpty
              ? find.textContaining('The characters drawn during the setup')
              : find.textContaining('The same pool'),
        )
        .data!;
    expect(caption(), startsWith('The characters drawn'), reason: 'the standard banner first');
    expect(find.byTooltip('Next banner'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(caption(), startsWith('The same pool'), reason: 'the weekly banner');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(caption(), startsWith('The same pool'), reason: 'nothing after the last');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(caption(), startsWith('The characters drawn'));
    await tester.tap(find.byTooltip('Next banner'));
    await _frames(tester);
    expect(caption(), startsWith('The same pool'));

    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(GachaScreen), findsNothing);
  });

  testWidgets('summon keeps to swiping on a phone', (tester) async {
    _screen(tester);
    final controller = await launchedGame(others: ['Alex', 'Sam', 'Robin', 'Kim']);
    await tester.pumpWidget(MaterialApp(home: GachaScreen(controller: controller)));
    await tester.pump();
    expect(find.byTooltip('Next banner'), findsNothing);
  });

  testWidgets('a single pull: → cuts the tape like a swipe, then Enter skips and continues', (tester) async {
    _screen(tester);
    await _push(tester, PullRevealScreen(outcomes: [_outcome('Sam', Rarity.hero)]), settle: false);
    GachaBox box() => tester.widget<GachaBox>(find.byType(GachaBox).first);
    expect(box().cut, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _frames(tester, const Duration(milliseconds: 200));
    expect(box().cut, inExclusiveRange(0, 1), reason: 'cutting along, like a swipe');
    await _until(tester, find.text('Tap to skip'));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Tap to continue'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byType(PullRevealScreen), findsNothing);
  });

  testWidgets('a multi-pull: → cuts, then hurries through every card to the overview, and Enter ends it', (
    tester,
  ) async {
    _screen(tester);
    final outcomes = [for (var i = 0; i < 3; i++) _outcome('Basic $i', Rarity.basic)];
    await _push(tester, PullRevealScreen(outcomes: outcomes), settle: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _until(tester, find.text('Tap to hurry'));

    // Hurry along through each card's reveal to the overview.
    for (var i = 0; i < 40 && find.text('Your pulls').evaluate().isEmpty; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your pulls'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(PullRevealScreen), findsNothing);
  });

  testWidgets('Esc closes a reveal', (tester) async {
    _screen(tester);
    await _push(tester, PullRevealScreen(outcomes: [_outcome('Sam', Rarity.basic)]), settle: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PullRevealScreen), findsNothing);
  });
}
