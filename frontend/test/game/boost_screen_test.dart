import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/boost_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

void main() {
  testWidgets("spreads the boost stars across yesterday's challengers", (tester) async {
    tester.view.physicalSize = const Size(400, 800);
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
    expect(find.textContaining('3 of 3 left'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    // Every challenger shows its own stars; boost stars go below them.
    final ownStars = find.descendant(
      of: find.bySemanticsLabel('3 stars of its own'),
      matching: find.byIcon(Icons.star_rounded),
    );
    expect(ownStars.hitTestable(), findsNWidgets(3));
    expect(find.text('Drop a boost star here').hitTestable(), findsOneWidget);

    Future<void> drag(Finder from, Finder to) async {
      final gesture = await tester.startGesture(tester.getCenter(from));
      await tester.pump(const Duration(milliseconds: 50));
      final end = tester.getCenter(to);
      await gesture.moveTo(Offset.lerp(tester.getCenter(from), end, 0.5)!);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(end);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Finder trayStar() => find.byTooltip('Give a star').hitTestable().first;
    Finder given(int target, int slot) => find.byKey(ValueKey('${targets[target].challenger.id}-$slot'));

    // Drag two stars from the tray onto the first challenger.
    final first = find.text(targets.first.challenger.title);
    await drag(trayStar(), first);
    await drag(trayStar(), first);
    expect(controller.boostTargets.first.stars, 2);
    expect(find.textContaining('1 of 3 left'), findsOneWidget);
    expect(given(0, 1), findsOneWidget);
    expect(given(0, 2), findsNothing, reason: 'no empty slots');
    expect(find.text('Drop a boost star here').hitTestable(), findsNothing);

    // Drag one back down to the tray, and tap to give it again.
    await drag(given(0, 1), find.textContaining('1 of 3 left'));
    expect(controller.boostTargets.first.stars, 1);
    await tester.tap(trayStar());
    await tester.pumpAndSettle();
    expect(controller.boostTargets.first.stars, 2);

    // On to the next one: the last star goes there, and none are left.
    await tester.tap(find.byTooltip('Next challenger'));
    await tester.pumpAndSettle();
    expect(find.text('Boost challengers 2/${targets.length}'), findsOneWidget);
    await drag(trayStar(), find.text(targets[1].challenger.title));
    expect(controller.boostTargets[1].stars, 1);
    expect(controller.canBoost, isFalse);
    expect(find.textContaining('All 3 stars given'), findsOneWidget);
    expect(find.byTooltip('Give a star'), findsNothing);

    // A tap takes one back; going back, the first one's stay.
    await tester.tap(given(1, 0));
    await tester.pumpAndSettle();
    expect(controller.boostStarsLeft, 1);
    await tester.tap(find.byTooltip('Previous challenger'));
    await tester.pumpAndSettle();
    expect(controller.boostTargets.first.stars, 2);
    expect(given(0, 1), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
