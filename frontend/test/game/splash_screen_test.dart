import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/api_client.dart';
import 'package:frontend/backend/api_game_session.dart';
import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/screens/signup_screen.dart';
import 'package:frontend/game/screens/splash_screen.dart';
import 'package:frontend/game/widgets/card_art.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../backend/fakes.dart';

FilledButton _button(WidgetTester tester) => tester.widget<FilledButton>(find.byType(FilledButton));

double _opacityOf(WidgetTester tester, Finder finder) =>
    tester.widget<Opacity>(find.ancestor(of: finder, matching: find.byType(Opacity)).first).opacity;

void main() {
  testWidgets('the title screen waits for the backend, and only its button goes in', (tester) async {
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
    await tester.pump(SplashScreen.intro);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text("ovid's"), findsOneWidget);
    expect(find.text('DRAWING DUEL'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    // Still loading: the button is off, and a loading circle turns below it.
    expect(_button(tester).onPressed, isNull);
    final spinner = find.bySemanticsLabel('Loading');
    expect(spinner, findsOneWidget);
    expect(tester.getTopLeft(spinner).dy, greaterThan(tester.getBottomLeft(find.byType(FilledButton)).dy));

    // The backend answered: the button is on, the circle gone.
    await tester.runAsync(session.start);
    // The standees float on and on, so the title screen never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_button(tester).onPressed, isNotNull);
    expect(find.bySemanticsLabel('Loading'), findsNothing);

    // Only the button goes in, not a tap elsewhere.
    await tester.tap(find.text('DRAWING DUEL'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.tap(find.text('Tap to start'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(SignupScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the title and the standees come in first, then the button fades in', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var started = false;
    await tester.pumpWidget(MaterialApp(home: SplashScreen(ready: true, onStart: () => started = true)));
    final title = find.text('DRAWING DUEL');
    final button = find.text('Tap to start');
    final standee = find.byType(Standee).first;
    double titleTop() => tester.getTopLeft(title).dy;
    bool standeeInView() {
      final rect = tester.getRect(standee);
      return rect.right > 0 && rect.left < 390;
    }

    // At first: the title above its place, the standees out of view, no button.
    final startTop = titleTop();
    expect(standeeInView(), isFalse);
    expect(_opacityOf(tester, button), 0);
    await tester.tap(button, warnIfMissed: false);
    expect(started, isFalse, reason: 'not before it shows');

    // The title has come in before the standees are all there and the button shows.
    await tester.pump(SplashScreen.intro * 0.5);
    expect(titleTop(), greaterThan(startTop));
    expect(_opacityOf(tester, button), 0);

    await tester.pump(SplashScreen.intro * 0.5);
    expect(standeeInView(), isTrue);
    expect(_opacityOf(tester, button), 1);
    await tester.pump();
    await tester.tap(button);
    expect(started, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the mockup is ready as soon as the button shows', (tester) async {
    await tester.pumpWidget(GameApp(session: MockGameSession(seed: 1)));
    await tester.pump(SplashScreen.intro);
    await tester.pump();
    expect(_button(tester).onPressed, isNotNull);
    await tester.tap(find.text('Tap to start'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(SignupScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sample standees float on both sides, and stay still for less motion', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: SplashScreen(ready: true, onStart: () {})));
    await tester.pump(SplashScreen.intro);
    final standees = find.byType(Standee);
    expect(standees, findsNWidgets(4));
    final sides = {for (final e in standees.evaluate()) tester.getCenter(find.byWidget(e.widget)).dx < 195};
    expect(sides, {true, false}, reason: 'left and right');
    final before = tester.getTopLeft(standees.first);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(standees.first), isNot(before), reason: 'floating');
    expect(tester.takeException(), isNull);

    // With less motion, everything is there at once, and nothing floats.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
        child: MaterialApp(home: SplashScreen(ready: true, onStart: () {})),
      ),
    );
    await tester.pump();
    expect(_opacityOf(tester, find.text('Tap to start')), 1);
    final still = tester.getTopLeft(standees.first);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(standees.first), still);
    await tester.pumpWidget(const SizedBox());
  });
}
