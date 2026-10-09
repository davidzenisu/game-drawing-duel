import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/mockup/mock_game_session.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';
import 'package:frontend/game/screens/setup_screen.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';

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

  testWidgets('joins a server by code and only offers free seats', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MockGameSession(seed: 1);
    await tester.pumpWidget(GameApp(session: controller));
    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join server'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Server code'), '123456');
    await tester.pump();
    await tester.tap(find.text('Find server'));
    await tester.pumpAndSettle();

    final preview = await controller.previewServer('123456');
    final seats = find.byType(RadioListTile<Player>);
    expect(seats, findsNWidgets(preview.players.length));
    for (final (i, player) in preview.players.indexed) {
      final tile = tester.widget<RadioListTile<Player>>(seats.at(i));
      expect(tile.enabled, !preview.joined.contains(player.id), reason: player.name);
    }
    // The admin's seat is labelled as such, other taken seats as joined.
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Already joined'), findsNWidgets(preview.joined.length - 1));

    // Your name is preselected; joining opens the lobby.
    final join = find.widgetWithText(FilledButton, 'Join server');
    await tester.ensureVisible(join);
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(find.text('Lobby'), findsOneWidget);
    expect(controller.you.name, 'Pat');
    expect(find.text('Waiting for the admin to start…'), findsOneWidget);

    // The simulated admin starts the setup once everyone joined.
    for (var i = 0; i < SetupPlan.maxPlayers && controller.phase == GamePhase.lobby; i++) {
      await tester.pump(controller.refreshInterval);
    }
    await tester.pumpAndSettle();
    expect(controller.phase, GamePhase.setup);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a test session is marked and can start without everyone', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MockGameSession(seed: 1);
    await tester.pumpWidget(GameApp(session: controller));
    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();

    final checkbox = find.widgetWithText(CheckboxListTile, 'Test session');
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    final create = find.widgetWithText(FilledButton, 'Create server');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.server.isTest, isTrue);
    expect(find.text('TEST SESSION'), findsOneWidget);
    // Nobody else joined yet, but a test session can start anyway.
    expect(controller.server.everyoneJoined, isFalse);
    final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start drawing'));
    expect(start.onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelling the server asks first and returns to the server screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MockGameSession(seed: 1);
    await tester.pumpWidget(GameApp(session: controller));
    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create server');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(controller.phase, GamePhase.lobby);

    await tester.tap(find.byTooltip('Cancel server'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel the server?'), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(controller.phase, GamePhase.lobby);

    await tester.tap(find.byTooltip('Cancel server'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel server'));
    await tester.pumpAndSettle();
    expect(controller.phase, GamePhase.server);
    expect(find.text('Create server'), findsWidgets);

    // Also from the setup, while the other players are drawing.
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await controller.startSetup();
    await tester.pumpAndSettle();
    expect(find.text('Initial drawings'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel server'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel server'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(controller.phase, GamePhase.server);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uploads and the launch show a progress circle', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = _SlowSession();
    await tester.pumpWidget(GameApp(session: controller));
    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();
    await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim'], isTest: true);
    await controller.startSetup();
    await tester.pumpAndSettle();

    for (final (i, assignment) in controller.assignments.indexed) {
      await tester.tap(find.widgetWithText(FilledButton, 'Draw').first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(SketchPad), const Offset(80, 60));
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Drawing $i');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      // The progress circle keeps spinning, so the screen never settles.
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Uploading…'), findsOneWidget, reason: assignment.prompt.label);
      expect(
        find.descendant(of: find.byType(SetupScreen), matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
      controller.release();
      await tester.pumpAndSettle();
      expect(find.text('Uploading…'), findsNothing);
      expect(find.text('"Drawing $i"'), findsOneWidget);
    }

    final launch = find.widgetWithText(FilledButton, 'Finish and launch');
    await tester.ensureVisible(launch);
    await tester.tap(launch);
    await tester.pump();
    expect(find.text('Launching…'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SetupScreen), matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    controller.release();
    await tester.pumpAndSettle();
    expect(controller.phase, GamePhase.daily);

    await tester.pumpWidget(const SizedBox());
  });
}

/// A mockup whose uploads and launch wait until [release]d.
class _SlowSession extends MockGameSession {
  _SlowSession() : super(seed: 1);

  Completer<void>? _pending;

  void release() => _pending?.complete();

  Future<void> _wait() async {
    _pending = Completer();
    await _pending!.future;
  }

  @override
  Future<void> submitSetupDrawing(DrawingAssignment assignment, Sketch sketch, String title) async {
    await _wait();
    await super.submitSetupDrawing(assignment, sketch, title);
  }

  @override
  Future<void> launch() async {
    await _wait();
    await super.launch();
  }
}
