import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/boost_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

void main() {
  testWidgets("spreads the boost stars across yesterday's challengers", (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const doodle = Sketch([
      Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
    ]);
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
    // Everyone writes and draws, so there are three challengers to boost.
    await controller.submitPrompt('Sunburnt', controller.promptCandidates.first);
    await controller.advanceDay();
    await controller.submitChallenger(doodle);
    await controller.advanceDay();
    final targets = controller.boostTargets;
    expect(targets, hasLength(Boost.challengers));

    bool? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => done = await Navigator.of(
              context,
            ).push<bool>(MaterialPageRoute(builder: (_) => BoostScreen(controller: controller))),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Boost challengers 1/${targets.length}'), findsOneWidget);
    expect(find.text(targets.first.challenger.title), findsOneWidget);
    expect(find.textContaining('3 of 3 stars left'), findsOneWidget);

    Future<void> tap(String tooltip) async {
      await tester.tap(find.byTooltip(tooltip).hitTestable());
      await tester.pumpAndSettle();
    }

    await tap('Give a star');
    await tap('Give a star');
    expect(controller.boostTargets.first.stars, 2);
    expect(find.textContaining('1 of 3 stars left'), findsOneWidget);

    // On to the next one, and back: the stars stay where they are.
    await tap('Next challenger');
    expect(find.text('Boost challengers 2/${targets.length}'), findsOneWidget);
    await tap('Give a star');
    expect(controller.boostTargets[1].stars, 1);
    expect(controller.canBoost, isFalse);
    final give = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add_rounded).hitTestable());
    expect(give.onPressed, isNull, reason: 'no stars left');
    await tap('Take a star back');
    expect(controller.boostStarsLeft, 1);
    await tap('Previous challenger');
    expect(controller.boostTargets.first.stars, 2);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
