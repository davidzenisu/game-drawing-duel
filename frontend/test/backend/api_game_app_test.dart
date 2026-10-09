import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/api_client.dart';
import 'package:frontend/backend/api_game_session.dart';
import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/game_app.dart';

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

    // No suggested names against the API: enter the other players.
    for (final name in ['Sam', 'Robin', 'Kim', 'Jo']) {
      await tester.enterText(find.widgetWithText(TextField, 'Add a player'), name);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    final create = find.widgetWithText(FilledButton, 'Create server');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.textContaining("isn't available yet"), findsOneWidget);
  });
}
