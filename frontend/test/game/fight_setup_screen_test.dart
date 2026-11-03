import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/upgrades.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/fight_setup_screen.dart';
import 'package:frontend/game/widgets/fight_stage.dart';
import 'package:frontend/mockup/mock_game_session.dart';

const _doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

Future<MockGameSession> _launched() async {
  // Day 1 is a Monday: the first week ends on day 7.
  final controller = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 10, 5, 12));
  await controller.signUp('Pat');
  await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
  while (!controller.server.everyoneJoined) {
    await controller.refreshServer();
  }
  await controller.startSetup();
  for (final (i, assignment) in controller.assignments.indexed) {
    await controller.submitSetupDrawing(assignment, _doodle, 'Drawing $i');
  }
  await controller.launch();
  return controller;
}

void main() {
  testWidgets('picking fighters shows the stars their win rates add for you or the challenger', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _launched();
    // Last week's fights give this week's win rates; find a day whose
    // challenger meets a player your characters have a win rate against.
    late OwnedCard pick;
    late int change;
    for (var found = false; !found;) {
      await controller.advanceDay();
      expect(controller.day, lessThan(15), reason: 'a star change within the second week');
      final rates = (await controller.winRates())!;
      final against = controller.fightChallenger?.subject;
      if (against == null) continue;
      for (final owned in controller.availableFighters) {
        // One to find in the roster by its title.
        if (controller.collection.where((o) => o.card.title == owned.card.title).length != 1) continue;
        final subject = owned.card.subject;
        change = rates.extraStars(subject, against) - rates.extraStars(against, subject);
        if (change != 0) {
          pick = owned;
          found = true;
          break;
        }
      }
    }

    await tester.pumpWidget(MaterialApp(home: FightSetupScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.byType(StarChangeBadge), findsNothing, reason: 'nobody picked yet');
    await tester.tap(find.text('Roster'));
    await tester.pumpAndSettle();
    final card = find.text(pick.card.title);
    await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).last);
    final label = '${change > 0 ? '+' : '−'}${change.abs()} ★';
    expect(find.text(label), findsWidgets, reason: 'shown in the roster');
    await tester.tap(card);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // On the stage, and summed up below it.
    expect(find.descendant(of: find.byType(FightStage), matching: find.text(label)), findsOneWidget);
    expect(
      find.text(change > 0 ? 'Win rates: your fighters +$change ★' : 'Win rates: the challenger +${-change} ★'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    await tester.pumpWidget(const SizedBox());
  });
}
