import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/screens/drawings_screen.dart';
import 'package:frontend/game/tutorials.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';

import '../helpers.dart';

void main() {
  testWidgets('admins pick a server, the setup or a day, and a drawing to see it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame(launchDate: firstMonday, day: 4, drawing: true);
    for (final tutorial in Tutorial.values) {
      await game.markTutorialSeen(tutorial.key);
    }
    await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: game)));
    await tester.pump();
    // The launch bonus greets first.
    await tester.tap(find.text("Let's go"));
    await tester.pumpAndSettle();
    await openAdminMenu(tester, 'Drawings');
    expect(find.byType(DrawingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.byType(SketchView), findsNothing);

    Future<void> pick(String field, String item) async {
      await tester.tap(find.widgetWithText(InputDecorator, field));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(item).last);
      await tester.pumpAndSettle();
    }

    await pick('Server', game.server.code);
    // The setup first, then the days with challengers.
    await tester.tap(find.widgetWithText(InputDecorator, 'Date'));
    await tester.pumpAndSettle();
    expect(find.text('Setup (initial drawings)').last, findsOneWidget);
    expect(find.textContaining('Day 2 · '), findsWidgets);
    await tester.tap(find.text('Setup (initial drawings)').last);
    await tester.pumpAndSettle();

    final setup = (await game.serverDrawings(game.server.code)).firstWhere((d) => d.day == null);
    await pick('Drawing', '${setup.subject}: ${setup.title} (by ${setup.artist})');
    expect(find.byType(SketchView), findsOneWidget);
    expect(find.text('${setup.subject}: ${setup.title}'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
