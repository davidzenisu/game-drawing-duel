import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/screens/arena_screen.dart';
import 'package:frontend/game/screens/ranking_screen.dart';
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
  testWidgets('votes by tap, key, swipe and "Can\'t decide", then the pack\'s stars', (tester) async {
    _phone(tester);
    final game = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 11, 4, 9));
    await game.startOnDayEight('Pat');
    await tester.pumpWidget(MaterialApp(home: ArenaScreen(controller: game)));
    await _settle(tester);
    expect(find.text('Which one is the better drawing?'), findsOneWidget);
    expect(find.text("Week 1's challengers"), findsOneWidget);
    expect(find.text('0 of ${Arena.pack} votes for today\'s ${Arena.packStars} ★'), findsOneWidget);

    Future<void> voted(int votes) async {
      await _settle(tester);
      expect(game.arena!.votesToday, votes);
    }

    // A tap on the left one.
    await tester.tap(find.byType(Card).at(1));
    await voted(1);
    // → picks the right one.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await voted(2);
    // A draw.
    await tester.tap(find.text("Can't decide"));
    await voted(3);
    // A swipe to the left picks the left one; a short drag picks nothing.
    await tester.drag(find.byType(Card).at(1), const Offset(-20, 0));
    await voted(3);
    await tester.drag(find.byType(Card).at(1), const Offset(-200, 0));
    await voted(4);

    final stars = game.stars;
    while (game.arena!.votesToday < Arena.pack) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
    }
    expect(game.stars, stars + Arena.packStars);
    expect(find.textContaining("Today's ${Arena.packStars} ★ earned."), findsOneWidget);
    expect(find.text('Which one is the better drawing?'), findsOneWidget, reason: 'voting goes on');
  });

  testWidgets('before the second week, the Arena says when it opens', (tester) async {
    _phone(tester);
    final game = await launchedGame();
    await tester.pumpWidget(MaterialApp(home: ArenaScreen(controller: game)));
    await _settle(tester);
    expect(find.text('The Arena opens next week'), findsOneWidget);
  });

  testWidgets("the week ranking's Arena view: this week's Arena, then the latest decided one", (tester) async {
    _phone(tester);
    final game = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 11, 4, 9));
    await game.startOnDayEight('Pat');
    await tester.pumpWidget(
      MaterialApp(
        home: RankingScreen(controller: game, view: RankingView.arena),
      ),
    );
    await _settle(tester);
    expect(find.textContaining("Week 1's"), findsOneWidget);
    expect(find.textContaining('ratings stay secret'), findsOneWidget);
    await tester.tap(find.text('Last week'));
    await _settle(tester);
    expect(find.textContaining('No Arena decided yet'), findsOneWidget);

    while (game.day < 15) {
      await game.advanceDay();
    }
    await tester.pumpWidget(
      MaterialApp(
        home: RankingScreen(
          key: const ValueKey('decided'),
          controller: game,
          view: RankingView.arena,
          period: StatPeriod.lastWeek,
        ),
      ),
    );
    await _settle(tester);
    expect(find.textContaining('Arena winner'), findsWidgets);
    expect(find.textContaining('#1 · Arena winner · ★★★★'), findsOneWidget);
  });
}
