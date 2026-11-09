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
  testWidgets('content editors add and retire prompts, each with its premade title', (tester) async {
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
    expect(find.text('No prompts for Enchanted Forest yet.'), findsOneWidget);

    // Volcano Lair: a description and its premade title, both needed.
    await tester.tap(find.text('Volcano Lair'));
    await settle();
    Finder field(String label) => find.widgetWithText(TextField, label);
    FilledButton add() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'));
    await tester.enterText(field('Description'), ' a sauna regular ');
    await tester.pump();
    expect(add().onPressed, isNull, reason: 'no premade title yet');
    await tester.enterText(field('Premade title'), 'Lord of the Top Bench');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle();
    expect(find.textContaining('used from tomorrow on'), findsOneWidget);
    expect(find.text('1 in use'), findsOneWidget);
    expect(find.text('Lord of the Top Bench'), findsOneWidget);
    expect(backend.hints.single, containsPair('premade_title', 'Lord of the Top Bench'));
    expect(backend.hints.single, containsPair('theme', 'volcano'));
    expect(backend.hints.single, containsPair('text', 'a sauna regular'));

    // The same description again is skipped and stays in the fields.
    await tester.enterText(field('Description'), 'a sauna regular');
    await tester.enterText(field('Premade title'), 'Another');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle();
    expect(find.text('Volcano Lair has this description already.'), findsOneWidget);
    expect(backend.hints, hasLength(1));

    // Premade titles are at most 60 characters.
    await tester.enterText(field('Premade title'), 'x' * 61);
    await tester.pump();
    expect(tester.widget<TextField>(field('Premade title')).controller!.text, hasLength(60));

    // Retiring asks first.
    await tester.tap(find.byTooltip('Retire'));
    await settle();
    expect(find.textContaining('still used for the rest of today'), findsOneWidget);
    await tester.tap(find.text('Retire'));
    await settle();
    expect(find.text('No prompts for Volcano Lair yet.'), findsOneWidget);
  });

  testWidgets('content editors add and retire starter prompts per type', (tester) async {
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

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tester.pumpWidget(MaterialApp(home: ContentScreen(controller: editor)));
    await settle();
    await tester.tap(find.text('Setup'));
    await settle();
    expect(find.textContaining('No starter prompts for this type yet'), findsOneWidget);
    expect(backend.requests.last.url.toString(), 'https://api.example/content/setup-hints?prompt=basic');

    await tester.tap(find.text('Mage ★★'));
    await settle();
    final field = find.widgetWithText(TextField, 'Starter prompt');
    await tester.enterText(field, ' their hidden talent ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle();
    expect(find.text('Added. It is given out from the next setup on.'), findsOneWidget);
    expect(find.text('1 in use'), findsOneWidget);
    expect(backend.setupHints.single, containsPair('prompt', 'mage'));
    expect(backend.setupHints.single, containsPair('text', 'their hidden talent'));

    // The same text again is skipped.
    await tester.enterText(field, 'their hidden talent');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle();
    expect(find.text('This type has this starter prompt already.'), findsOneWidget);
    expect(backend.setupHints, hasLength(1));

    // Other types have their own.
    await tester.tap(find.text('Rogue ★★'));
    await settle();
    expect(find.widgetWithText(ListTile, 'their hidden talent'), findsNothing);
    expect(find.textContaining('No starter prompts for this type yet'), findsOneWidget);
    await tester.tap(find.text('Mage ★★'));
    await settle();

    await tester.tap(find.byTooltip('Retire'));
    await settle();
    expect(find.text('Retire this starter prompt?'), findsOneWidget);
    await tester.tap(find.text('Retire'));
    await settle();
    expect(find.textContaining('No starter prompts for this type yet'), findsOneWidget);
    expect(backend.setupHints.single, containsPair('retired', true));
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
