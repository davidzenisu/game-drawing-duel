import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/ranking_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

const _doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

Future<MockGameSession> _launched() async {
  // Day 1 is a Monday: the first week ends on day 7.
  final controller = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 10, 5, 12));
  await controller.signUp('Pat');
  await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
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
  testWidgets('the week ranking lists every challenger, the hero first', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _launched();

    await tester.pumpWidget(MaterialApp(home: RankingScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No ranking yet'), findsOneWidget);

    for (var day = 1; day < 8; day++) {
      await controller.advanceDay();
    }
    final ranking = (await controller.weekRanking())!;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: RankingScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.textContaining('${ranking.challengers.length} challengers'), findsOneWidget);
    final hero = ranking.challengers.first;
    expect(find.text('${hero.card.subject} · ${hero.card.title}'), findsWidgets);
    expect(find.textContaining('Weekly hero'), findsOneWidget);
    expect(find.text('${hero.stars} ★').first, findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'places are numbered');
    await tester.pumpWidget(const SizedBox());
  });
}
