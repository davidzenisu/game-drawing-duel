import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/boost_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

void main() {
  testWidgets("boosts one of yesterday's challengers, once a day", (tester) async {
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
    for (var day = 1; day < 4; day++) {
      await controller.advanceDay();
    }
    final targets = controller.boostTargets;
    expect(targets, isNotEmpty);
    final first = targets.first;

    bool? boosted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => boosted = await Navigator.of(
              context,
            ).push<bool>(MaterialPageRoute(builder: (_) => BoostScreen(controller: controller))),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Boost a challenger 1/${targets.length}'), findsOneWidget);
    expect(find.textContaining('${first.challenger.subject} · ${first.challenger.title}'), findsOneWidget);

    await tester.tap(find.text('Boost ${first.challenger.subject}'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('You boosted ${first.challenger.subject} today'), findsOneWidget);
    expect(controller.boostedChallengerId, first.challenger.id);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(boosted, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
