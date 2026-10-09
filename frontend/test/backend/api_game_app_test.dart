import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/api_client.dart';
import 'package:frontend/backend/api_game_session.dart';
import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/rules/models.dart';

import 'fakes.dart';

void main() {
  testWidgets('signs up against the API through the shared screens', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    final session = ApiGameSession(
      api: ApiClient(
        baseUrl: 'https://api.example',
        auth: FakeAuthClient(profile: const AuthProfile(givenName: 'Pat')),
        httpClient: backend.client,
      ),
    );
    await tester.pumpWidget(GameApp(session: session));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.runAsync(session.start);
    await tester.pumpAndSettle();

    // Prefilled from the social login; no mockup hints.
    expect(find.widgetWithText(TextField, 'Pat'), findsOneWidget);
    expect(find.textContaining('Mockup mode'), findsNothing);
    expect(find.text('Sign up with social login'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Patricia');
    await tester.tap(find.text('Finish account'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Hi Patricia!'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);

    // No suggested names against the API: enter the other players.
    for (final name in ['Sam', 'Robin', 'Kim', 'Jo']) {
      await tester.enterText(find.widgetWithText(TextField, 'Add a player'), name);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    final create = find.widgetWithText(FilledButton, 'Create server');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Lobby'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('Players 1/5'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to play with your friends.'), findsOneWidget);
  });

  testWidgets('a test session ends the day for everyone through the hub', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    final session = ApiGameSession(
      api: ApiClient(
        baseUrl: 'https://api.example',
        auth: FakeAuthClient(
          token: 'alex',
          profile: const AuthProfile(givenName: 'Alex'),
        ),
        httpClient: backend.client,
      ),
    );
    // Alone in a launched test session.
    await tester.runAsync(() async {
      await session.start();
      await session.signUp('Alex');
      await session.createServer(['Sam', 'Robin', 'Kim', 'Jo'], isTest: true);
      await session.startSetup();
      for (final assignment in session.assignments) {
        await session.submitSetupDrawing(assignment, Sketch.empty, assignment.prompt.label);
      }
      await session.launch();
    });
    await tester.pumpWidget(GameApp(session: session));
    await tester.pumpAndSettle();
    // The launch dialog.
    await tester.tap(find.text("Let's go"));
    await tester.pumpAndSettle();

    expect(find.text('Day 1 · Enchanted Forest'), findsOneWidget);
    expect(find.text('Nobody ended the day yet'), findsOneWidget);
    expect(find.byTooltip('Start the next day for everyone'), findsOneWidget);

    await tester.tap(find.text('End my day'));
    await tester.pumpAndSettle();
    // Steps are still open today.
    await tester.tap(find.widgetWithText(FilledButton, 'End my day'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    // Alone, ending the day starts the next one.
    expect(session.day, 2);
    expect(find.text('Day 2 · Hot Sandy Beaches'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
