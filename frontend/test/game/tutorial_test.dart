import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/tutorials.dart';
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
  test('every tutorial has pages and a key the API accepts', () {
    expect(Tutorial.values.map((t) => t.key).toSet(), hasLength(Tutorial.values.length));
    for (final tutorial in Tutorial.values) {
      expect(tutorial.key, matches(RegExp(r'^[a-z0-9-]{1,40}$')));
      expect(tutorial.pages, isNotEmpty, reason: tutorial.key);
    }
  });

  testWidgets('intros show once, before the step, and can be replayed, on a phone', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _launched();

    await tester.pumpWidget(GameApp(session: controller));
    await tester.pumpAndSettle();
    // The welcome first: next through its pages, then the launch bonus.
    expect(find.text('Welcome'), findsOneWidget);
    expect(controller.tutorialsSeen, {Tutorial.welcome.key});
    for (var page = 1; page < Tutorial.welcome.pages.length; page++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text(Tutorial.welcome.pages.last.title), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Let's go"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'the hub fits a phone');

    // A step's intro comes before its screen, the first time only.
    final prompt = find.textContaining('Choose a challenger');
    await tester.tap(prompt);
    await tester.pumpAndSettle();
    expect(find.text(Tutorial.prompt.pages.first.title), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the intro fits a phone');
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(controller.tutorialsSeen, containsAll([Tutorial.welcome.key, Tutorial.prompt.key]));
    expect(find.text(Tutorial.prompt.pages.first.title), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(prompt);
    await tester.pumpAndSettle();
    expect(find.text(Tutorial.prompt.pages.first.title), findsNothing, reason: 'seen already');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // "How to play" replays any of them.
    await tester.tap(find.byTooltip('How to play'));
    await tester.pumpAndSettle();
    final gacha = find.text(Tutorial.gacha.title);
    await tester.ensureVisible(gacha);
    await tester.tap(gacha);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text(Tutorial.gacha.pages.first.title)),
      findsOneWidget,
    );
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(controller.tutorialsSeen, isNot(contains(Tutorial.gacha.key)), reason: 'replays change nothing');
    await tester.pumpWidget(const SizedBox());
  });
}
