import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/api_client.dart';
import 'package:frontend/backend/api_game_session.dart';
import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/screens/signup_screen.dart';
import 'package:frontend/game/screens/splash_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../backend/fakes.dart';

void main() {
  testWidgets('the title screen waits for the backend, then one tap goes in', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = ApiGameSession(
      api: ApiClient(
        baseUrl: 'https://api.example',
        auth: FakeAuthClient(profile: const AuthProfile(givenName: 'Pat')),
        httpClient: FakeBackend().client,
      ),
    );
    await tester.pumpWidget(GameApp(session: session));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text("ovid's"), findsOneWidget);
    expect(find.text('DRAWING DUEL'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    // Still loading: the button waits, and taps do nothing.
    expect(find.text('Loading…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.tap(find.byType(SplashScreen));
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);

    // The backend answered: the button is on, and the title screen stays.
    await tester.runAsync(session.start);
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Tap to start'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);

    // A tap anywhere goes in.
    await tester.tap(find.text('DRAWING DUEL'));
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(SignupScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the mockup is ready at once', (tester) async {
    await tester.pumpWidget(GameApp(session: MockGameSession(seed: 1)));
    await tester.pump();
    expect(find.text('Tap to start'), findsOneWidget);
    await tester.tap(find.text('Tap to start'));
    await tester.pumpAndSettle();
    expect(find.byType(SignupScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
