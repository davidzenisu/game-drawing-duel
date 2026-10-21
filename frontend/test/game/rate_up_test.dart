import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/gacha_screen.dart';
import 'package:frontend/game/widgets/banner_art.dart';
import 'package:frontend/game/widgets/card_art.dart';
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

Finder _bannerArt(GachaBanner banner) => find.byWidgetPredicate((w) => w is BannerArt && w.banner == banner);

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
    // Titles can repeat: the premade ones of a description are shared.
    final titles = [hero, ...legends].map((card) => card.title);
    for (final title in titles.toSet()) {
      expect(
        find.descendant(of: banner, matching: find.text(title)),
        findsNWidgets(titles.where((t) => t == title).length),
        reason: 'named, summoned or not',
      );
    }
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    // The weekly banner shows them off, drawings and all.
    final art = tester.widget<BannerArt>(_bannerArt(GachaBanner.weekly));
    expect({for (final card in art.featured) card.id}, controller.rateUp);
    final standees = tester.widgetList<Standee>(
      find.descendant(of: _bannerArt(GachaBanner.weekly), matching: find.byType(Standee)),
    );
    expect(standees.map((s) => s.card.id).toSet(), controller.rateUp);
    expect(standees.every((s) => !s.hidden), isTrue, reason: 'a spoiler of what you can pull');

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
    // The standard banner comes first, with three of its legends.
    final standard = tester.widget<BannerArt>(_bannerArt(GachaBanner.standard));
    final setupLegends = controller.pool.where((c) => c.day == 0 && c.rarity == Rarity.legend);
    expect(standard.featured, hasLength(min(3, setupLegends.length)));
    expect(standard.featured.every((c) => c.day == 0 && c.rarity == Rarity.legend), isTrue);
    expect(standard.featured.map((c) => c.id).toSet(), hasLength(standard.featured.length), reason: 'all different');
    expect(find.text('★★★★ guaranteed within your next 10 standard pulls'), findsOneWidget);
    expect(find.text('Hero'), findsNothing, reason: 'no 3 stars among the setup drawings');
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    // Swiping over shows the weekly banner, closed before the first finale.
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<BannerArt>(_bannerArt(GachaBanner.weekly)).locked, isTrue);
    expect(find.text('Opens with the first finale'), findsOneWidget);
    for (final label in ['Pull ×1', 'Pull ×10']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull, reason: label);
    }
    await tester.tap(find.bySemanticsLabel('Standard banner'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('★★★★ guaranteed within your next 10 standard pulls'), findsOneWidget);

    for (var day = 1; day < 8; day++) {
      await controller.advanceDay();
    }
    await tester.pump();
    expect(find.text('Rate up this week'), findsOneWidget, reason: 'the weekly banner comes first once open');
    expect(tester.widget<BannerArt>(_bannerArt(GachaBanner.weekly)).locked, isFalse);
    expect(find.textContaining('standard pulls'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Standard banner'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rate up this week'), findsNothing);
    expect(find.text('★★★★ guaranteed within your next 10 standard pulls'), findsOneWidget);
    expect(
      tester.widget<BannerArt>(_bannerArt(GachaBanner.standard)).featured.map((c) => c.id),
      standard.featured.map((c) => c.id),
      reason: 'the same three legends while you stay',
    );

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
