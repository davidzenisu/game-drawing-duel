import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/api_client.dart';
import 'package:frontend/backend/api_game_session.dart';
import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/screens/content_screen.dart';
import 'package:frontend/game/widgets/content_editor_button.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../backend/fakes.dart';

void main() {
  testWidgets('content editors add and retire descriptions per theme', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend()..contentEditors.add('kim');
    final editor = ApiGameSession(
      api: ApiClient(
        baseUrl: 'https://api.example',
        auth: FakeAuthClient(token: 'kim', profile: const AuthProfile()),
        httpClient: backend.client,
      ),
    );
    await tester.runAsync(() async {
      await editor.start();
      await editor.signUp('Kim');
    });

    // Lets the fake backend answer; the loading spinner never settles.
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tester.pumpWidget(MaterialApp(home: ContentScreen(controller: editor)));
    await settle();
    expect(find.text('No descriptions for Enchanted Forest yet.'), findsOneWidget);

    // Volcano Lair: add two, one per line.
    await tester.tap(find.text('Volcano Lair'));
    await settle();
    await tester.enterText(find.byType(TextField), 'a sauna regular\n\n a toast burner ');
    await tester.pump();
    await tester.tap(find.text('Add 2'));
    await settle();
    expect(find.textContaining('Added 2.'), findsOneWidget);
    expect(find.text('2 in use'), findsOneWidget);
    expect(backend.content['hints']!.map((e) => e['theme']), ['volcano', 'volcano']);

    // Retiring asks first.
    await tester.tap(find.byTooltip('Retire').first);
    await settle();
    expect(find.textContaining('still used for the rest of today'), findsOneWidget);
    await tester.tap(find.text('Retire'));
    await settle();
    expect(find.text('1 in use'), findsOneWidget);
    expect(find.text('a sauna regular'), findsNothing);

    // Premade titles are at most 60 characters.
    await tester.tap(find.text('Premade titles'));
    await settle();
    await tester.enterText(find.byType(TextField).last, 'x' * 61);
    await tester.pump();
    expect(find.text('At most 60 characters per premade title'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add').last).onPressed, isNull);
  });

  testWidgets('content editors and the mockup get the button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [ContentEditorButton(session: MockGameSession(seed: 1))]),
        ),
      ),
    );
    expect(find.byTooltip('Game content'), findsOneWidget, reason: 'the mockup lets you try it');

    final backend = FakeBackend()..contentEditors.add('kim');
    final player = ApiGameSession(
      api: ApiClient(
        baseUrl: 'https://api.example',
        auth: FakeAuthClient(token: 'sam', profile: const AuthProfile()),
        httpClient: backend.client,
      ),
    );
    await tester.runAsync(() async {
      await player.start();
      await player.signUp('Sam');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [ContentEditorButton(session: player)]),
        ),
      ),
    );
    expect(find.byTooltip('Game content'), findsNothing, reason: 'players without the permission');

    final editor = ApiGameSession(
      api: ApiClient(
        baseUrl: 'https://api.example',
        auth: FakeAuthClient(token: 'kim', profile: const AuthProfile()),
        httpClient: backend.client,
      ),
    );
    await tester.runAsync(() async {
      await editor.start();
      await editor.signUp('Kim');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [ContentEditorButton(session: editor)]),
        ),
      ),
    );
    expect(find.byTooltip('Game content'), findsOneWidget);
  });
}
