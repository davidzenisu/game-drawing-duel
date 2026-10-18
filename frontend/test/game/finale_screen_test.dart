import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/finale_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

/// Records the finale votes it passes on.
class _RecordingSession extends MockGameSession {
  _RecordingSession() : super(seed: 1, launchDate: DateTime.utc(2026, 10, 5, 12));

  final votes = <(String chosen, String other)>[];

  @override
  Future<void> voteFinale(CharacterCard chosen, CharacterCard other) {
    votes.add((chosen.id, other.id));
    return super.voteFinale(chosen, other);
  }
}

void main() {
  testWidgets('swipe or tap to pick one of each pair, on a phone', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const doodle = Sketch([
      Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
    ]);
    final controller = _RecordingSession();
    await controller.signUp('Pat');
    await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
    while (!controller.server.everyoneJoined) {
      await controller.refreshServer();
    }
    await controller.startSetup();
    for (final assignment in controller.assignments) {
      await controller.submitSetupDrawing(assignment, doodle, 'Title');
    }
    await controller.launch();
    // Day 1 is a Monday, day 7 the Sunday of the finale.
    for (var day = 1; day < 7; day++) {
      await controller.advanceDay();
    }
    final ballot = controller.finale!;
    expect(ballot.pairs, greaterThanOrEqualTo(3));

    await tester.pumpWidget(MaterialApp(home: FinaleScreen(controller: controller)));
    await tester.pump();
    expect(find.text('Finale · 0/${ballot.pairs}'), findsOneWidget);

    Future<(String, String)> pick(Future<void> Function() gesture) async {
      final (left, right) = controller.finale!.pair!;
      await gesture();
      await tester.pumpAndSettle();
      final vote = controller.votes.last;
      expect({vote.$1, vote.$2}, {left.id, right.id});
      return (left.id, right.id);
    }

    // Swiping left picks the left one, swiping right the right one.
    var (left, right) = await pick(() => tester.drag(find.text('VS'), const Offset(-200, 0)));
    expect(controller.votes.last, (left, right));
    (left, right) = await pick(() => tester.drag(find.text('VS'), const Offset(200, 0)));
    expect(controller.votes.last, (right, left));
    expect(find.text('Finale · 2/${ballot.pairs}'), findsOneWidget);

    // A short drag picks nothing.
    await tester.drag(find.text('VS'), const Offset(-20, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(controller.votes, hasLength(2));

    // The button below each side picks it too.
    final (_, nextRight) = controller.finale!.pair!;
    (left, right) = await pick(() => tester.tap(find.byIcon(Icons.arrow_forward_rounded)));
    expect(controller.votes.last, (nextRight.id, left));
    expect(tester.takeException(), isNull, reason: 'fits a phone screen');

    for (var pair = controller.finale!.pair; pair != null; pair = controller.finale!.pair) {
      await controller.voteFinale(pair.$1, pair.$2);
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('You voted on all ${ballot.pairs} pairs'), findsOneWidget);
  });
}
