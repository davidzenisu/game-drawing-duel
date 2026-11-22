import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/gacha_screen.dart';
import 'package:frontend/game/widgets/banner_art.dart';
import 'package:frontend/game/widgets/card_art.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

/// A mockup game played to the Monday after its first finale.
Future<MockGameSession> _afterTheFinale() async {
  // Day 1 is a Monday: the finale is on day 7, its heroes join on day 8.
  return launchedGame(launchDate: firstMonday, day: 8);
}

Finder _bannerArt(GachaBanner banner) => find.byWidgetPredicate((w) => w is BannerArt && w.banner == banner);

void main() {
  testWidgets('the weekly heroes are rate-up, on summon and in the pool', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _afterTheFinale();
    final heroes = [for (final hero in controller.weeklyHeroes) hero.card];
    expect([for (final hero in heroes) hero.rarity], [Rarity.legend, Rarity.hero, Rarity.adventurer]);
    // A legend among them: no starter legend joins them.
    expect(controller.rateUp, {for (final hero in heroes) hero.id});
    final hero = heroes[1];
    final chances = GachaMachine.characterChances(controller.pool, controller.rateUp);

    await tester.pumpWidget(MaterialApp(home: GachaScreen(controller: controller)));
    await tester.pump();
    final banner = find.ancestor(of: find.text('Rate up this week'), matching: find.byType(Card));
    expect(banner, findsOneWidget);
    for (final subject in heroes.map((card) => card.subject).toSet()) {
      expect(
        find.descendant(of: banner, matching: find.text(subject)),
        findsNWidgets(heroes.where((card) => card.subject == subject).length),
      );
    }
    // Titles can repeat: the premade ones of a description are shared.
    final titles = heroes.map((card) => card.title);
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
    expect(find.text('Weekly hero'), findsNWidgets(heroes.length));
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
      await controller.submitSetupDrawing(assignment, doodle, 'Title');
    }
    await controller.launch();
    await tester.pumpWidget(MaterialApp(home: GachaScreen(controller: controller)));
    await tester.pump();
    // The standard banner comes first, with the week's showcase from the
    // setup: a basic of the first player, a 2 star of the second and a legend
    // of the third.
    final standard = tester.widget<BannerArt>(_bannerArt(GachaBanner.standard));
    final players = [for (final p in controller.server.players) p.name];
    expect(
      [for (final c in standard.featured) (c.rarity, c.subject, c.day)],
      [(Rarity.basic, players[0], 0), (Rarity.adventurer, players[1], 0), (Rarity.legend, players[2], 0)],
    );
    expect(find.text('★★★★ guaranteed within your next 10 standard pulls'), findsOneWidget);
    expect(find.text('Hero'), findsNothing, reason: 'no 3 stars among the setup drawings');
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    // Swiping over shows the weekly banner, closed before the first finale.
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<BannerArt>(_bannerArt(GachaBanner.weekly)).locked, isTrue);
    expect(find.text('Opens once a finale crowns weekly heroes'), findsOneWidget);
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
    // A new week: each slot moves on to the next player.
    expect(
      [for (final c in tester.widget<BannerArt>(_bannerArt(GachaBanner.standard)).featured) (c.rarity, c.subject)],
      [(Rarity.basic, players[1]), (Rarity.adventurer, players[2]), (Rarity.legend, players[3])],
    );

    final pull = find.text('Pull ×1');
    await tester.ensureVisible(pull);
    await tester.pump();
    await tester.tap(pull);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pull heroes'), findsOneWidget, reason: 'asks first');
    expect(find.text('to pull 1 hero?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pull'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.collection.every((o) => o.card.day == 0), isTrue, reason: 'only setup drawings on standard');
    expect(controller.gachaStatus.totalPulls, 1);
    expect(controller.gachaStatus.beginnerPullsLeft, anyOf(isNull, 9));
    await tester.pumpWidget(const SizedBox());
  });

  test("pulls from the mockup's pool favour its rate-up", () async {
    final controller = await _afterTheFinale();
    // The 3 star of the week's heroes.
    final hero = controller.weeklyHeroes.firstWhere((h) => h.card.rarity == Rarity.hero).card;
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
