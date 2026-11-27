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
    await tester.pumpWidget(GameApp(session: session, splash: false));
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

    // Renamed from the account menu.
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Patricia'), findsOneWidget);
    await tester.tap(find.text('Change name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Patricia'), ' Trish ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Hi Trish!'), findsOneWidget);
    expect(backend.players.values.single['first_name'], 'Trish');

    // Joining comes first.
    await tester.tap(find.widgetWithText(Tab, 'Create server'));
    await tester.pumpAndSettle();
    // Another name on this server only.
    await tester.tap(find.text('Trish (you, admin)'));
    await tester.pumpAndSettle();
    expect(find.text('Your name on this server'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Trish'), 'Pat');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pat (you, admin)'), findsOneWidget);
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
    expect(backend.servers['123456']!.seats.first['name'], 'Pat');
    expect(backend.players.values.single['first_name'], 'Trish', reason: 'the account keeps its name');

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
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
    await tester.pumpWidget(GameApp(session: session, splash: false));
    await tester.pumpAndSettle();
    // The welcome intro first, stored with the account, then the launch dialog.
    expect(find.text('A few minutes a day'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(backend.tutorialsSeen['alex'], {'welcome'});
    expect(backend.requests.where((r) => r.method == 'PUT').last.url.path, '/me/tutorials/welcome');
    await tester.tap(find.text("Let's go"));
    await tester.pumpAndSettle();

    expect((find.text('Day 1').evaluate().length, find.text('Enchanted Forest').evaluate().length), (1, 1));
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
    expect((find.text('Day 2').evaluate().length, find.text('Hot Sandy Beaches').evaluate().length), (1, 1));

    await tester.pumpWidget(const SizedBox());
  });

  group('errors never sign you out', () {
    ApiGameSession sessionFor(FakeAuthClient auth, FakeBackend backend) => ApiGameSession(
      api: ApiClient(baseUrl: 'https://api.example', auth: auth, httpClient: backend.client),
      retryDelay: Duration.zero,
    );

    testWidgets('a rejected token shows on the sign-in screen, which offers to sign out', (tester) async {
      final auth = FakeAuthClient(profile: const AuthProfile(givenName: 'Pat'));
      final backend = FakeBackend()..rejectAll = (status: 401, detail: 'Invalid access token');
      final session = sessionFor(auth, backend);
      await tester.pumpWidget(GameApp(session: session, splash: false));
      await tester.runAsync(session.start);
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid access token'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(auth.signOuts, 1);
      expect(find.textContaining('Invalid access token'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed load offers to try again', (tester) async {
      final auth = FakeAuthClient(profile: const AuthProfile(givenName: 'Sam'));
      final backend = FakeBackend()
        ..players['test-token'] = {'id': 'player-uuid-3', 'first_name': 'Sam'}
        ..rejectAll = (status: 503, detail: 'Service unavailable');
      final session = sessionFor(auth, backend);
      await tester.pumpWidget(GameApp(session: session, splash: false));
      await tester.runAsync(session.start);
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load the game"), findsOneWidget);
      expect(find.textContaining('Service unavailable'), findsOneWidget);

      backend.rejectAll = null;
      await tester.tap(find.text('Try again'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Hi Sam!'), findsOneWidget);
      expect(auth.signOuts, 0);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a token rejected mid-game shows the error with a sign-out action', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = FakeAuthClient(profile: const AuthProfile(givenName: 'Sam'));
      final backend = FakeBackend()..players['test-token'] = {'id': 'player-uuid-3', 'first_name': 'Sam'};
      final session = sessionFor(auth, backend);
      await tester.pumpWidget(GameApp(session: session, splash: false));
      await tester.runAsync(session.start);
      await tester.pumpAndSettle();
      expect(find.text('Hi Sam!'), findsOneWidget);

      backend.rejectAll = (status: 401, detail: 'Invalid access token');
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Sam'), 'Samuel');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid access token'), findsOneWidget);
      expect(find.textContaining('sign out and sign in again'), findsOneWidget);
      expect(auth.signOuts, 0, reason: 'you stay where you are');

      await tester.tap(find.widgetWithText(SnackBarAction, 'Sign out'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(auth.signOuts, 1);
      expect(find.text('Sign in'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
