import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/tutorials.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

const _steps = ['Choose a challenger', 'Draw a challenger', 'Boost challengers', 'Pick your fighters'];

Future<List<String>> _shown(WidgetTester tester, MockGameSession controller) async {
  for (final tutorial in Tutorial.values) {
    await controller.markTutorialSeen(tutorial.key);
  }
  await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: controller)));
  await tester.pump();
  final shown = [
    for (final title in [..._steps, 'Week ranking', 'Send a hurry'])
      if (find.textContaining(title, skipOffstage: false).evaluate().isNotEmpty) title,
  ];
  await tester.pumpWidget(const SizedBox());
  return shown;
}

void main() {
  testWidgets('a regular server shows the steps of the loop as they start', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    expect(await _shown(tester, await launchedGame(launchDate: firstMonday)), ['Choose a challenger']);
    expect(await _shown(tester, await launchedGame(launchDate: firstMonday, day: 2)), [
      'Choose a challenger',
      'Draw a challenger',
      'Send a hurry',
    ]);
    expect(await _shown(tester, await launchedGame(launchDate: firstMonday, day: 4)), [..._steps, 'Send a hurry']);
    expect(await _shown(tester, await launchedGame(launchDate: firstMonday, day: 8)), [
      ..._steps,
      'Week ranking',
      'Send a hurry',
    ], reason: 'a week is over');
  });

  testWidgets('speed mode drops the steps its last days have no use for', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<List<String>> onDay(int day) async => _shown(
      tester,
      await launchedGame(others: ['Alex', 'Sam', 'Robin', 'Kim'], launchDate: firstMonday, speed: true, day: day),
    );

    // Prompts on days 1 to 3, drawn on 2 to 4, boosted on 3 to 5, fought on 4 to 6.
    expect(await onDay(4), [..._steps.skip(1), 'Send a hurry'], reason: 'no prompts after day 3');
    expect(await onDay(5), ['Boost challengers', 'Pick your fighters']);
    expect(await onDay(6), ['Pick your fighters'], reason: 'no week ranking in speed mode');
  });
}
