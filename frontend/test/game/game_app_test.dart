import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/mockup/mock_game_session.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';
import 'package:frontend/game/screens/collection_screen.dart';
import 'package:frontend/game/screens/prompt_screen.dart';
import 'package:frontend/game/screens/setup_screen.dart';
import 'package:frontend/game/widgets/cancel_server_button.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';
import 'package:frontend/theme/palette.dart';

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

  /// Cancels the server through both confirmations.
  Future<void> confirmCancel(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cancel server'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel server'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: CancelServerButton.countdownSeconds));
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel for everyone'));
    await tester.pumpAndSettle();
  }

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

    // The second confirmation unlocks after a countdown.
    await tester.tap(find.byTooltip('Cancel server'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel server'));
    await tester.pumpAndSettle();
    expect(find.text('Are you sure?'), findsOneWidget);
    final countdown = find.widgetWithText(FilledButton, 'Cancel for everyone (10)');
    expect(tester.widget<FilledButton>(countdown).onPressed, isNull);
    await tester.pump(const Duration(seconds: 9));
    expect(find.widgetWithText(FilledButton, 'Cancel for everyone (1)'), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(controller.phase, GamePhase.lobby);

    await confirmCancel(tester);
    expect(controller.phase, GamePhase.server);
    expect(find.text('Create server'), findsWidgets);

    // Also from the setup, while the other players are drawing.
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await controller.startSetup();
    await tester.pumpAndSettle();
    expect(find.text('Initial drawings'), findsOneWidget);
    await confirmCancel(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(controller.phase, GamePhase.server);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('draws in brown', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MockGameSession(seed: 1);
    await tester.pumpWidget(GameApp(session: controller));
    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();
    await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim'], isTest: true);
    await controller.startSetup();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Draw').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedContainer && (widget.decoration as BoxDecoration?)?.color == AppPalette.brushBrown,
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(SketchPad), const Offset(80, 60));
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Brown');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    final drawing = controller.setupDrawing(controller.assignments.first)!;
    expect(drawing.sketch.strokes.single.color, AppPalette.brushBrown);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the hub lists the challengers you encountered', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const doodle = Sketch([
      Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
    ]);
    final controller = MockGameSession(seed: 1);
    await controller.signUp('Pat');
    await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim'], isTest: true);
    await controller.startSetup();
    for (final assignment in controller.assignments) {
      await controller.submitSetupDrawing(assignment, doodle, 'Title');
    }
    await controller.launch();
    await controller.submitPrompt('Sunburnt', controller.promptCandidates.first);
    await controller.advanceDay();
    await controller.submitChallenger(doodle);
    await tester.pumpWidget(GameApp(session: controller));
    await tester.pumpAndSettle();
    if (find.text("Let's go").evaluate().isNotEmpty) {
      await tester.tap(find.text("Let's go"));
      await tester.pumpAndSettle();
    }

    final card = find.text('Challengers');
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('No fights decided yet'), findsOneWidget);
    expect(find.textContaining('Day 2 · by Pat'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the collection shows characters not summoned yet as question marks', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const doodle = Sketch([
      Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
    ]);
    final controller = MockGameSession(seed: 1);
    await controller.signUp('Pat');
    await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim']);
    while (!controller.server.everyoneJoined) {
      await controller.refreshServer();
    }
    await controller.startSetup();
    for (final assignment in controller.assignments) {
      await controller.submitSetupDrawing(assignment, doodle, 'Title');
    }
    await controller.launch();
    await tester.pumpWidget(MaterialApp(home: CollectionScreen(controller: controller)));
    await tester.pumpAndSettle();

    final owned = controller.collection.length;
    final locked = controller.pool.length - owned;
    expect(locked, greaterThan(0));
    expect(find.text('Collection $owned/${controller.pool.length}'), findsOneWidget);
    expect(find.text('???'), findsNWidgets(locked));
    expect(find.byIcon(Icons.question_mark_rounded), findsNWidgets(locked));
    final hidden = controller.pool.firstWhere((c) => !controller.collection.any((o) => o.card.id == c.id));
    expect(find.text(hidden.title), findsNothing, reason: 'the title stays a secret');

    // Tapping a hidden one opens nothing.
    await tester.tap(find.text('???').first);
    await tester.pumpAndSettle();
    expect(find.byType(CharacterDetailScreen), findsNothing);
  });

  testWidgets('choosing a challenger: a person and a title', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const doodle = Sketch([
      Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
    ]);
    final controller = MockGameSession(seed: 1);
    await controller.signUp('Pat');
    await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim'], isTest: true);
    await controller.startSetup();
    for (final assignment in controller.assignments) {
      await controller.submitSetupDrawing(assignment, doodle, 'Title');
    }
    await controller.launch();
    await tester.pumpWidget(MaterialApp(home: PromptScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Who is ${controller.promptHint}?'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Pat'), findsNothing, reason: 'anyone but yourself');
    final send = find.widgetWithText(FilledButton, 'Send prompt');
    await tester.enterText(find.byType(TextField), 'Sunburnt');
    await tester.pump();
    expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'nobody chosen yet');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sam'));
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(controller.yourPrompt!.subject.name, 'Sam');
    expect(controller.yourPrompt!.title, 'Sunburnt');
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
