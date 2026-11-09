import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/screens/send_gift_screen.dart';
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

  testWidgets('the admin form sends a gift to chosen players', (tester) async {
    _phone(tester);
    final game = await _hub(tester);
    await game.acceptGift(game.gifts.single);
    await openAdminMenu(tester, 'Send a gift');
    expect(find.byType(SendGiftScreen), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    final send = find.widgetWithText(FilledButton, 'Send gift');
    FilledButton button() => tester.widget<FilledButton>(send);
    // All servers by default; it needs a message.
    expect(find.text('Send to all servers (and all players)'), findsOneWidget);
    expect(button().onPressed, isNull);

    // One server, chosen players: you.
    await tester.tap(find.text('Send to all servers (and all players)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick a server'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(game.server.code).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to all players of that server'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, game.you.name));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Pulls per player'), '5');
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Thanks for testing!');
    await tester.pump();
    expect(button().onPressed, isNotNull);

    // Out of range pulls can't be sent.
    await tester.enterText(find.widgetWithText(TextField, 'Pulls per player'), '0');
    await tester.pump();
    expect(button().onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Pulls per player'), '5');
    await tester.pump();

    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.byType(SendGiftScreen), findsNothing);
    expect(find.text('Sent 5 pulls to 1 player.'), findsOneWidget);
    expect(game.gifts.single.message, 'Thanks for testing!');
    expect(find.byTooltip('Notifications (1 new)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
