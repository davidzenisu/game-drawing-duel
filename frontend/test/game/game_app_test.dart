import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/mockup/mock_game_session.dart';
import 'package:frontend/game/game_app.dart';

void main() {
  testWidgets('walks from signup through the lobby into the drawing setup', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MockGameSession(seed: 1);
    await tester.pumpWidget(GameApp(session: controller));

    expect(find.text('Drawing Duel'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();

    expect(find.text('Hi Pat!'), findsOneWidget);
    // The mockup has no account to sign out of.
    expect(find.byTooltip('Sign out'), findsNothing);
    final create = find.widgetWithText(FilledButton, 'Create server');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(find.text('Lobby'), findsOneWidget);
    expect(find.text(controller.server.code), findsOneWidget);
    // Friends join one after another.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(controller.server.everyoneJoined, isTrue);

    await tester.ensureVisible(find.text('Start drawing'));
    await tester.tap(find.text('Start drawing'));
    await tester.pumpAndSettle();
    expect(find.text('Draw your friends'), findsOneWidget);

    // Stop the background timers before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
