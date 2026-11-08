import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/screens/server_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

void main() {
  testWidgets('joining comes first, under a note on the game for new players', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MockGameSession(seed: 1);
    await tester.pumpWidget(GameApp(session: controller, splash: false));
    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerScreen), findsOneWidget);

    // The tabs: Join, then Create; Join is open.
    final tabs = tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text).toList();
    expect(tabs, ['Join server', 'Create server']);
    expect(find.widgetWithText(TextField, 'Server code'), findsOneWidget);

    // The note says what the game is, and that it's all explained later.
    expect(find.textContaining('draw each other as heroes and challengers', findRichText: true), findsOneWidget);
    expect(find.textContaining('explained step by step once you join or create', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    // Dismissed for good.
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('explained step by step', findRichText: true), findsNothing);
    expect(controller.tutorialsSeen, contains(ServerScreen.introKey));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('text can be selected and copied, e.g. a heading', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MockGameSession(seed: 1);
    await tester.pumpWidget(GameApp(session: controller, splash: false));
    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();

    // On its first word.
    await tester.longPressAt(tester.getTopLeft(find.text('Got a code from a friend?')) + const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget, reason: 'the selection menu');
    await tester.pumpWidget(const SizedBox());
  });
}
