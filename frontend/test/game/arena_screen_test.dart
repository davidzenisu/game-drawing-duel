import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/screens/arena_screen.dart';
import 'package:frontend/game/screens/ranking_screen.dart';
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

    // An arrow by each drawing points the way that picks it: → top right,
    // ← bottom left; the hints below say it's the card you drag.
    final card = find.byKey(const ValueKey('arena-card'));
    final right = find.descendant(of: card, matching: find.byKey(const ValueKey('arena-arrow-right')));
    final left = find.descendant(of: card, matching: find.byKey(const ValueKey('arena-arrow-left')));
    expect(right, findsOneWidget);
    expect(left, findsOneWidget);
    final cardCenter = tester.getCenter(card);
    expect(tester.getCenter(right).dx, greaterThan(cardCenter.dx));
    expect(tester.getCenter(right).dy, lessThan(cardCenter.dy));
    expect(tester.getCenter(left).dx, lessThan(cardCenter.dx));
    expect(tester.getCenter(left).dy, greaterThan(cardCenter.dy));
    expect(find.text('← Drag the card'), findsOneWidget);
    expect(find.text('Drag the card →'), findsOneWidget);
    double opacity(Finder arrow) =>
        tester.widget<Opacity>(find.descendant(of: arrow, matching: find.byType(Opacity)).first).opacity;

    // Dragging stamps the side the card leans toward and fades the other
    // side's arrow; a short drag goes back.
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
    expect(opacity(right), lessThan(0.5));
    expect(opacity(left), 1);
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

    // Only challengers with enough matchups are ranked and crowned; the
    // others are listed below, unranked.
    final ranking = (await game.arenaRanking())!;
    expect(ranking.winners.every((w) => w.qualified), isTrue);
    final unranked = ranking.challengers.where((c) => !c.qualified).toList();
    expect(unranked, isNotEmpty, reason: 'the demo has a few without enough matchups');
    expect(ranking.challengers.skipWhile((c) => c.qualified).every((c) => !c.qualified), isTrue, reason: 'last');
    await tester.scrollUntilVisible(find.text('Not enough matchups'), 200);
    expect(find.text('${unranked.first.matchups} of ${Arena.minMatchups} matchups'), findsWidgets);
  });
}
