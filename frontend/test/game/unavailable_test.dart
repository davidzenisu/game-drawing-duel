import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/screens/heroes_menu_screen.dart';
import 'package:frontend/game/tutorials.dart';
import 'package:frontend/game/unavailable.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

Future<MockGameSession> _speed(int day) =>
    launchedGame(others: ['Alex', 'Sam', 'Robin', 'Kim'], launchDate: firstMonday, speed: true, day: day);

void main() {
  test('a regular server explains the steps that have not started', () async {
    final game = await launchedGame(launchDate: firstMonday);
    expect(Unavailable.draw(game), 'Drawing starts on day 2.');
    expect(Unavailable.boost(game), 'Boosting starts on day 3.');
    final day3 = await launchedGame(launchDate: firstMonday, day: 3);
    expect(Unavailable.boost(day3), "You didn't draw yesterday's challenger, so you can't boost today.");
    expect(Unavailable.fight(game), 'Fighting starts on day 4.');
    expect(Unavailable.weekRanking(game), contains('once the first week is over'));
    expect(Unavailable.winRates(game), 'Win rates open once the first week is over, on Monday.');
    expect(Unavailable.fightReplay(game), 'The first fights are on day 4: replay them from day 5 on.');

    await game.submitPrompt('Sunburnt', game.promptCandidates.first);
    expect(Unavailable.prompt(game), 'Done: you chose ${game.yourPrompt!.subject.name} today.');
    await game.sendHurry(game.otherPlayers.first);
    expect(Unavailable.hurry(game), "Done: you sent today's hurry to ${game.otherPlayers.first.name}.");
  });

  test('speed mode explains the steps it is done with', () async {
    final day5 = await _speed(5);
    expect(Unavailable.prompt(day5), contains('speed mode ends it on day 3'));
    expect(Unavailable.draw(day5), contains('speed mode ends it on day 4'));
    expect(Unavailable.hurry(day5), contains("speed mode's last drawings are on day 4"));
    expect(Unavailable.winRates(day5), 'Speed mode has no win rates.');
    expect(Unavailable.weekRanking(day5), contains('at the end instead'));

    final day6 = await _speed(6);
    expect(Unavailable.boost(day6), contains('speed mode ends it on day 5'));

    final over = await _speed(7);
    expect(over.sessionOver, isTrue);
    for (final reason in [Unavailable.prompt, Unavailable.draw, Unavailable.boost, Unavailable.fight]) {
      expect(reason(over), contains('The speed session is over'));
    }
  });

  test('without a hero ready to fight, fighting is greyed out', () async {
    // In speed mode you only own your basic one, which rests after its fight.
    final game = await _speed(4);
    await game.submitFighters(game.availableFighters);
    expect(Unavailable.fight(game), isNull, reason: 'fought today');
    await game.advanceDay();
    expect(game.fightChallenger, isNotNull);
    expect(game.availableFighters, isEmpty);
    expect(game.hasOpenSteps, isFalse, reason: 'nothing left to do');
    expect(
      Unavailable.fight(game),
      "No heroes are available for fighting today: they're all resting after their fights. "
      'The first one is back tomorrow.',
    );
  });

  testWidgets('tapping a greyed out button tells why', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame(launchDate: firstMonday);
    for (final tutorial in Tutorial.values) {
      await game.markTutorialSeen(tutorial.key);
    }
    await game.pull(game.tickets);
    await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: game)));
    await tester.pump();
    await tester.tap(find.text('Boost challengers'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Boosting starts on day 3.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    await tester.pumpWidget(MaterialApp(home: HeroesMenuScreen(controller: game)));
    await tester.pump();
    await tester.tap(find.text('Fight replay'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('The first fights are on day 4: replay them from day 5 on.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
  });
}
