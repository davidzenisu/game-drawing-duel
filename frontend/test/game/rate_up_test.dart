import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/gacha_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

const _doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

/// A mockup game played to the Monday after its first finale.
Future<MockGameSession> _afterTheFinale() async {
  final controller = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 10, 5, 12));
  await controller.signUp('Pat');
  await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
  while (!controller.server.everyoneJoined) {
    await controller.refreshServer();
  }
  await controller.startSetup();
  for (final assignment in controller.assignments) {
    await controller.submitSetupDrawing(assignment, _doodle, 'Title');
  }
  await controller.launch();
  // Day 1 is a Monday: the finale is on day 7, its hero joins on day 8.
  for (var day = 1; day < 8; day++) {
    await controller.advanceDay();
  }
  return controller;
}

void main() {
  testWidgets('the weekly hero and their legend are rate-up, on summon and in the pool', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _afterTheFinale();
    final hero = controller.weeklyHero!.card;
    final legends = [
      for (final card in controller.pool)
        if (card.rarity == Rarity.legend && card.subject == hero.subject) card,
    ];
    expect(controller.rateUp, {hero.id, for (final legend in legends) legend.id});
    final chances = GachaMachine.characterChances(controller.pool, controller.rateUp);

    await tester.pumpWidget(MaterialApp(home: GachaScreen(controller: controller)));
    await tester.pump();
    final banner = find.ancestor(of: find.text('Rate up this week'), matching: find.byType(Card));
    expect(banner, findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text(hero.subject)), findsNWidgets(1 + legends.length));
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    final open = find.text('See what you can pull');
    await tester.ensureVisible(open);
    await tester.pump();
    await tester.tap(open);
    // Upgrade effects keep animating, so the screen never settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rate up'), findsNWidgets(controller.rateUp.length));
    expect(find.text('Weekly hero'), findsOneWidget);
    expect(chances[hero.id], greaterThan(chances[controller.pool.firstWhere((c) => c.rarity == Rarity.basic).id]!));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the standard banner is always there, the weekly one from the first finale on', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 10, 5, 12));
    await controller.signUp('Pat');
    await controller.createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
    while (!controller.server.everyoneJoined) {
      await controller.refreshServer();
    }
    await controller.startSetup();
    for (final assignment in controller.assignments) {
      await controller.submitSetupDrawing(assignment, _doodle, 'Title');
    }
    await controller.launch();
    await tester.pumpWidget(MaterialApp(home: GachaScreen(controller: controller)));
    await tester.pump();
    final weekly = find.ancestor(of: find.text('Weekly'), matching: find.byType(InkWell));
    expect(tester.widget<InkWell>(weekly).onTap, isNull, reason: 'closed before the first finale');
    expect(find.textContaining('opens with the first finale'), findsOneWidget);
    expect(find.text('★★★★ guaranteed within your next 10 standard pulls'), findsOneWidget);
    expect(find.text('Hero'), findsNothing, reason: 'no 3 stars among the setup drawings');

    for (var day = 1; day < 8; day++) {
      await controller.advanceDay();
    }
    await tester.pump();
    expect(find.text('Rate up this week'), findsOneWidget, reason: 'the weekly banner comes first once open');
    expect(find.textContaining('standard pulls'), findsNothing);
    await tester.tap(find.text('Standard'));
    await tester.pump();
    expect(find.text('Rate up this week'), findsNothing);
    expect(find.text('★★★★ guaranteed within your next 10 standard pulls'), findsOneWidget);

    final pull = find.text('Pull ×1');
    await tester.ensureVisible(pull);
    await tester.pump();
    await tester.tap(pull);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.collection.every((o) => o.card.day == 0), isTrue, reason: 'only setup drawings on standard');
    expect(controller.gachaStatus.totalPulls, 1);
    expect(controller.gachaStatus.beginnerPullsLeft, anyOf(isNull, 9));
    await tester.pumpWidget(const SizedBox());
  });

  test("pulls from the mockup's pool favour its rate-up", () async {
    final controller = await _afterTheFinale();
    final hero = controller.weeklyHero!.card;
    final heroes = controller.pool.where((c) => c.rarity == Rarity.hero).length;
    final gacha = GachaMachine(random: Random(3));
    var landed = 0, picked = 0;
    for (var i = 0; i < 20000; i++) {
      final card = gacha.pull(controller.pool, banner: GachaBanner.weekly, rateUp: controller.rateUp);
      if (card.rarity != Rarity.hero) continue;
      landed++;
      if (card.id == hero.id) picked++;
    }
    // Half of the 3 star pulls, or all of them if it's the only one.
    expect(picked / landed, closeTo(heroes == 1 ? 1 : GachaMachine.rateUp / 100, 0.05));
  });
}
