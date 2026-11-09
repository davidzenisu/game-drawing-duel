import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/tutorials.dart';
import 'package:frontend/game/widgets/notification_board.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<MockGameSession> _hub(WidgetTester tester) async {
  final game = await launchedGame(launchDate: firstMonday);
  for (final tutorial in Tutorial.values) {
    await game.markTutorialSeen(tutorial.key);
  }
  await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: game)));
  await tester.pump();
  // The launch bonus greets first.
  await tester.tap(find.text("Let's go"));
  await tester.pumpAndSettle();
  return game;
}

void main() {
  testWidgets('a gift waits on the board and its pulls count once accepted', (tester) async {
    _phone(tester);
    final game = await _hub(tester);
    expect(tester.takeException(), isNull, reason: 'the app bar fits a phone');
    // The mockup's welcome gift.
    expect(game.gifts, hasLength(1));
    expect(find.byTooltip('Notifications (1 new)'), findsOneWidget);
    final before = game.tickets;

    await tester.tap(find.byType(NotificationBoardButton));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationBoard), findsOneWidget);
    expect(find.textContaining('Welcome to Drawing Duel'), findsOneWidget);
    expect(find.text('+3 pulls'), findsOneWidget);
    expect(game.tickets, before, reason: 'not before it is accepted');

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(game.tickets, before + 3);
    expect(game.gifts, isEmpty);
    expect(find.text('Nothing new. Gifts and news show up here.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
