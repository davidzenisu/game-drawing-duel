import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/screens/arena_screen.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Lets the vote's animation and the next matchup come in.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('the card is dragged toward the better one, or thrown with ← / →; "Can\'t decide" is a draw', (
    tester,
  ) async {
    _phone(tester);
    final game = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 11, 4, 9));
    await game.startOnDayEight('Pat');
    await tester.pumpWidget(MaterialApp(home: ArenaScreen(controller: game)));
    await _settle(tester);
    expect(find.text("Week 1's challengers"), findsOneWidget);
    expect(find.text('0 of ${Arena.pack} for ${Arena.packStars} ★'), findsOneWidget);

    Future<void> voted(int votes) async {
      await _settle(tester);
      expect(game.arena!.votesToday, votes);
    }

    // Dragging stamps the side the card leans toward; a short drag goes back.
    final card = find.byKey(const ValueKey('arena-card'));
    final gesture = await tester.startGesture(tester.getCenter(card));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(find.text('BETTER'), findsOneWidget);
    expect(
      tester.getCenter(find.text('BETTER')).dy,
      greaterThan(tester.getCenter(card).dy),
      reason: 'dragged left: the one bottom left',
    );
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    expect(
      tester.getCenter(find.text('BETTER')).dy,
      lessThan(tester.getCenter(card).dy),
      reason: 'dragged right: the one top right',
    );
    await gesture.moveBy(const Offset(-70, 0));
    await gesture.up();
    await voted(0);
    expect(find.text('BETTER'), findsNothing, reason: 'back in the middle');

    // Far enough, it flies off: a vote for the left one.
    await tester.drag(card, const Offset(-200, 0));
    await voted(1);
    await tester.drag(card, const Offset(200, 0));
    await voted(2);
    // → and ← throw it too.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await voted(3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await voted(4);
    // A draw.
    await tester.tap(find.text("Can't decide"));
    await voted(5);

    final stars = game.stars;
    while (game.arena!.votesToday < Arena.pack) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
    }
    expect(game.stars, stars + Arena.packStars);
    expect(find.textContaining('${Arena.packStars} ★ earned'), findsOneWidget);
    expect(find.text("Can't decide"), findsOneWidget, reason: 'voting goes on');
  });

  testWidgets('the drawings take up the screen, on a phone and on a computer', (tester) async {
    final game = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 11, 4, 9));
    await game.startOnDayEight('Pat');
    for (final (size, minWidth) in [(const Size(400, 900), 190.0), (const Size(1400, 900), 200.0)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: ArenaScreen(key: ValueKey(size), controller: game),
        ),
      );
      await _settle(tester);
      // Both drawings of the matchup, and of the next one below.
      expect(find.byType(SketchView), findsNWidgets(4));
      final width = tester.getSize(find.byType(SketchView).last).width;
      expect(width, greaterThan(minWidth), reason: '$size');
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('before the second week, the Arena says when it opens', (tester) async {
    _phone(tester);
    final game = await launchedGame();
    await tester.pumpWidget(MaterialApp(home: ArenaScreen(controller: game)));
    await _settle(tester);
    expect(find.text('The Arena opens next week'), findsOneWidget);
  });
}
