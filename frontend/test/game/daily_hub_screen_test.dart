import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/screens/drawing_recap_screen.dart';
import 'package:frontend/game/screens/drawing_screen.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';
import 'package:frontend/game/widgets/ticket_chip.dart';
import 'package:frontend/game/screens/gacha_screen.dart';
import 'package:frontend/game/screens/heroes_menu_screen.dart';
import 'package:frontend/game/tutorials.dart';
import 'package:frontend/game/widgets/hurry_button.dart';
import 'package:frontend/game/widgets/hub_tile.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

const _steps = ['Choose a challenger', 'Draw a challenger', 'Boost challengers', 'Pick your fighters'];

Future<void> _seenAll(MockGameSession controller) async {
  for (final tutorial in Tutorial.values) {
    await controller.markTutorialSeen(tutorial.key);
  }
}

bool _enabled(WidgetTester tester, String title) =>
    tester.widget<HubTile>(find.widgetWithText(HubTile, title)).onTap != null;

/// The hub's steps that can be done today; all four are always shown.
Future<List<String>> _open(WidgetTester tester, MockGameSession controller) async {
  await _seenAll(controller);
  await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: controller)));
  await tester.pump();
  for (final title in _steps) {
    expect(find.widgetWithText(HubTile, title), findsOneWidget, reason: title);
  }
  final open = [
    for (final title in _steps)
      if (_enabled(tester, title)) title,
  ];
  expect(tester.takeException(), isNull, reason: 'fits a phone');
  await tester.pumpWidget(const SizedBox());
  return open;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a regular server greys out the steps that have not started', (tester) async {
    _phone(tester);
    expect(await _open(tester, await launchedGame(launchDate: firstMonday)), ['Choose a challenger']);
    expect(await _open(tester, await launchedGame(launchDate: firstMonday, day: 2)), _steps.take(2));
    expect(await _open(tester, await launchedGame(launchDate: firstMonday, day: 4, drawing: true)), _steps);
    // Without yesterday's drawing, no boosts.
    expect(await _open(tester, await launchedGame(launchDate: firstMonday, day: 4)), [
      'Choose a challenger',
      'Draw a challenger',
      'Pick your fighters',
    ]);
  });

  testWidgets('speed mode greys out the steps its last days have no use for', (tester) async {
    _phone(tester);
    Future<List<String>> onDay(int day) async => _open(
      tester,
      await launchedGame(
        others: ['Alex', 'Sam', 'Robin', 'Kim'],
        launchDate: firstMonday,
        speed: true,
        day: day,
        drawing: true,
      ),
    );

    // Prompts on days 1 to 3, drawn on 2 to 4, boosted on 3 to 5, fought on 4 to 6.
    expect(await onDay(4), _steps.skip(1), reason: 'no prompts after day 3');
    expect(await onDay(5), _steps.skip(2));
    expect(await onDay(6), _steps.skip(3));
  });

  testWidgets('the heroes menu has summoning and the rest, greyed out when it does not apply', (tester) async {
    _phone(tester);
    final controller = await launchedGame(launchDate: firstMonday);
    await _seenAll(controller);
    await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: controller)));
    await tester.pump();
    // The launch bonus greets first.
    await tester.tap(find.text("Let's go"));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Heroes'));
    await tester.tap(find.text('Heroes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HeroesMenuScreen), findsOneWidget);
    expect(find.text('Send a hurry'), findsNothing, reason: 'on the hub');
    expect(find.byType(SummonTile), findsOneWidget);
    expect(find.text('${controller.tickets} pulls ready'), findsOneWidget);
    expect(
      {
        for (final title in ['Hero List', 'Challengers', 'Win rates', 'Fight replay', 'Week ranking'])
          title: _enabled(tester, title),
      },
      {
        'Hero List': true,
        'Challengers': true,
        'Win rates': false, // not before the first week is over
        'Fight replay': false, // no past fights yet
        'Week ranking': false, // the first week isn't over
      },
    );
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    await tester.tap(find.byType(SummonTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GachaScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the hurry sits on the hub, above the drawing step', (tester) async {
    _phone(tester);
    final controller = await launchedGame(launchDate: firstMonday);
    await _seenAll(controller);
    await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: controller)));
    await tester.pump();
    await tester.tap(find.text("Let's go"));
    await tester.pumpAndSettle();
    final hurry = find.byType(HurryButton);
    expect(hurry, findsOneWidget);
    // Next to the day's title, in the column of the drawing step.
    final draw = tester.getRect(find.widgetWithText(HubTile, 'Draw a challenger'));
    final button = tester.getRect(hurry);
    expect(button.bottom, lessThan(draw.top));
    expect(button.center.dx, closeTo(draw.center.dx, 1));
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    // Free once a day: sent, it's done.
    await tester.tap(find.text('Send a hurry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(controller.otherPlayers.first.name).last);
    await tester.pumpAndSettle();
    expect(controller.hurrySentTo, controller.otherPlayers.first);
    expect(find.text('Hurry sent'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on day 8, the week ranking is on', (tester) async {
    _phone(tester);
    final controller = await launchedGame(launchDate: firstMonday, day: 8);
    await _seenAll(controller);
    await tester.pumpWidget(MaterialApp(home: HeroesMenuScreen(controller: controller)));
    await tester.pump();
    expect(_enabled(tester, 'Week ranking'), isTrue);
    expect(_enabled(tester, 'Win rates'), isTrue, reason: 'the first week is over');
    expect(_enabled(tester, 'Fight replay'), isTrue, reason: 'the fights of days 4 to 7');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after Done the drawing uploads first, then its recap shows, then the pull is celebrated', (
    tester,
  ) async {
    _phone(tester);
    final controller = _SlowUpload();
    await controller.signUp('Pat');
    await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
    while (!controller.server.everyoneJoined) {
      await controller.refreshServer();
    }
    await controller.startSetup();
    for (final assignment in controller.assignments) {
      await controller.submitSetupDrawing(assignment, doodle, 'Title');
    }
    await controller.launch();
    await controller.advanceDay();
    await _seenAll(controller);
    await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: controller)));
    await tester.pumpAndSettle();
    final tickets = controller.tickets;
    // The launch bonus greets first.
    if (find.text("Let's go").evaluate().isNotEmpty) {
      await tester.tap(find.text("Let's go"));
      await tester.pumpAndSettle();
    }

    await tester.ensureVisible(find.widgetWithText(HubTile, 'Draw a challenger'));
    await tester.tap(find.widgetWithText(HubTile, 'Draw a challenger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ready'));
    await tester.pump();
    await tester.dragFrom(tester.getRect(find.byType(SketchPad)).center, const Offset(60, 30));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();

    // Uploading: the drawing screen stays, saying so, and nothing else shows.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Saving your drawing…'), findsOneWidget);
      expect(find.byType(DrawingRecapScreen), findsNothing);
      expect(find.byType(PullsReceived), findsNothing);
    }

    // Uploaded: the recap takes its place, and the pull waits.
    controller.upload.complete();
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PullsReceived), findsNothing, reason: 'not over the recap');
    }
    expect(find.byType(DrawingScreen), findsNothing);
    expect(find.byType(DrawingRecapScreen), findsOneWidget);
    expect(controller.tickets, tickets + 1);

    // Back on the hub, the pull is celebrated.
    await tester.tap(find.text('Done · +1 pull'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PullsReceived), findsOneWidget);
    expect(find.text('+1 pull'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}

/// A mockup whose challenger upload takes until [upload] completes, like a
/// slow connection.
class _SlowUpload extends MockGameSession {
  _SlowUpload() : super(seed: 1);

  final upload = Completer<void>();

  @override
  Future<void> submitChallenger(Sketch sketch) async {
    await upload.future;
    await super.submitChallenger(sketch);
  }
}
