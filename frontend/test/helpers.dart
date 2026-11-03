import 'dart:ui';

import 'package:frontend/game/rules/models.dart';
import 'package:frontend/mockup/mock_game_session.dart';

/// A one-stroke drawing for tests that need any drawing at all.
const doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

/// A Monday: launched on it, days 1 to 7 are the first week and day 8
/// starts the next.
final firstMonday = DateTime.utc(2026, 10, 5, 12);

/// A mockup game you (Pat) created with [others], with everyone joined, your
/// setup drawings done, launched and moved on to [day]: its canned demo day,
/// with nothing done on the days before. Your drawings are titled "Title",
/// or "Drawing 0", "Drawing 1"… with [numberedTitles].
Future<MockGameSession> launchedGame({
  List<String> others = const ['Alex', 'Sam', 'Robin', 'Kim', 'Jo'],
  int seed = 1,
  DateTime? launchDate,
  bool speed = false,
  bool numberedTitles = false,
  int day = 1,
}) async {
  final game = MockGameSession(seed: seed, launchDate: launchDate);
  await game.signUp('Pat');
  await game.createServer(others, speed: speed);
  while (!game.server.everyoneJoined) {
    await game.refreshServer();
  }
  await game.startSetup();
  for (final (i, assignment) in game.assignments.indexed) {
    await game.submitSetupDrawing(assignment, doodle, numberedTitles ? 'Drawing $i' : 'Title');
  }
  await game.launch();
  while (game.day < day) {
    await game.advanceDay();
  }
  return game;
}
