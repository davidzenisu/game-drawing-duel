import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/api_client.dart';
import 'package:frontend/backend/api_game_session.dart';
import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/screens/content_screen.dart';
import 'package:frontend/game/screens/server_screen.dart';
import 'package:frontend/mockup/mockup_shell.dart';

import '../backend/fakes.dart';
import '../helpers.dart';

void main() {
  Future<ApiGameSession> signedUp(WidgetTester tester, FakeBackend backend, String token, String name) async {
    final session = ApiGameSession(
      api: ApiClient(
        baseUrl: 'https://api.example',
        auth: FakeAuthClient(token: token, profile: const AuthProfile()),
        httpClient: backend.client,
      ),
    );
    await tester.runAsync(() async {
      await session.start();
      await session.signUp(name);
    });
    return session;
  }

  testWidgets('only players who manage servers can try the mockup', (tester) async {
    final backend = FakeBackend()..serverManagers.add('alex');
    final player = await signedUp(tester, backend, 'sam', 'Sam');
    expect(player.canManageServers, isFalse);
    await tester.pumpWidget(MaterialApp(home: ServerScreen(controller: player)));
    await tester.pump();
    expect(await adminMenuItems(tester), isNot(contains('Try the mockup')));

    final admin = await signedUp(tester, backend, 'alex', 'Alex');
    expect(admin.canManageServers, isTrue);
    await tester.pumpWidget(MaterialApp(home: ServerScreen(controller: admin)));
    await tester.pump();
    expect(await adminMenuItems(tester), ['Try the mockup', 'Send a gift', 'Drawings']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the mockup opens over the real app, keeps its bar, and exits without a trace', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend()..serverManagers.add('alex');
    final admin = await signedUp(tester, backend, 'alex', 'Alex');
    await tester.pumpWidget(MaterialApp(home: ServerScreen(controller: admin)));
    await tester.pump();

    await openAdminMenu(tester, 'Try the mockup');
    expect(find.byType(MockupShell), findsOneWidget);
    expect(find.text('Mockup: sample data, nothing is saved'), findsOneWidget);
    expect(find.text('Start on day 8'), findsOneWidget, reason: "the mockup's own start");
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerScreen), findsOneWidget, reason: "the mockup's, the real one is underneath");
    expect(await adminMenuItems(tester), isNot(contains('Try the mockup')), reason: 'no mockup in the mockup');

    // Its screens open under the bar, and back goes back within the mockup.
    await openAdminMenu(tester, 'Game content');
    expect(find.byType(ContentScreen), findsOneWidget);
    expect(find.text('Mockup: sample data, nothing is saved'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ContentScreen), findsNothing);
    expect(find.byType(MockupShell), findsOneWidget);

    // With the keyboard open, the screen still has room for what's typed.
    await openAdminMenu(tester, 'Game content');
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await tester.pump();
    // The content screen's body (a Center) gets the room the keyboard leaves.
    final body = find.descendant(of: find.byType(ContentScreen), matching: find.byType(Center)).first;
    final keyboardTop = 900.0 - 400;
    expect(tester.getBottomLeft(body).dy, closeTo(keyboardTop, 1), reason: 'it reaches down to the keyboard');
    expect(tester.getSize(body).height, greaterThan(250), reason: 'the keyboard taken away once, not twice');
    tester.view.resetViewInsets();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(find.byType(MockupShell), findsNothing);
    expect(await adminMenuItems(tester), contains('Try the mockup'), reason: 'back in the real app');
    expect(admin.isMockup, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
