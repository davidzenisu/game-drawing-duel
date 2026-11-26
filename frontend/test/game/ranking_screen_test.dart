import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/player_stats_view.dart';
import 'package:frontend/game/screens/ranking_detail_screen.dart';
import 'package:frontend/game/screens/ranking_screen.dart';
import 'package:frontend/game/widgets/card_art.dart';

import '../helpers.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('weeks are numbered from the launch week, Monday to Sunday', () async {
    // Launched on a Wednesday: week 1 is days 1 to 5, week 2 starts on Monday, day 6.
    final game = await launchedGame(launchDate: firstMonday.add(const Duration(days: 2)));
    for (final day in [1, 1, 2, 3, 6, 9]) {
      while (game.day < day) {
        await game.advanceDay();
      }
      expect(
        [
          for (final d in [1, 5, 6, 12, 13]) game.weekOf(d),
        ],
        [1, 1, 2, 2, 3],
        reason: 'on day $day',
      );
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('a full roster of ten has ten colors in the challenger pie ($brightness)', (tester) async {
      final weeks = [for (var i = 0; i < 10; i++) PlayerWeek(name: 'P$i', position: i, chosen: 1)];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: SingleChildScrollView(child: PlayersDashboard(weeks: weeks)),
          ),
        ),
      );
      final dots = [
        for (final box in tester.widgetList<Container>(find.byType(Container)))
          if (box.decoration case BoxDecoration(shape: BoxShape.circle, :final color?)) color,
      ];
      expect(dots, hasLength(10));
      expect(dots.toSet(), hasLength(10), reason: 'every player has a color of their own');
      final grey = ThemeData(brightness: brightness).colorScheme.outline;
      expect(dots, isNot(contains(grey)));
    });
  }

  test('tied players share a place, the next one skips theirs', () {
    final [a, b, c, d] = const [
      Player(id: 'a', name: 'A'),
      Player(id: 'b', name: 'B'),
      Player(id: 'c', name: 'C'),
      Player(id: 'd', name: 'D'),
    ];
    final stat = PlayerStat.rank(PlayerStatKind.mostWins, [(a, 1, 0), (b, 3, 1), (c, 1, 0), (d, 3, 0)]);
    expect(
      [for (final p in stat.players) (p.player.name, p.value, p.place, p.first)],
      [('B', 3, 1, true), ('D', 3, 1, true), ('A', 1, 3, false), ('C', 1, 3, false)],
    );
    final none = PlayerStat.rank(PlayerStatKind.busyStreak, [(a, 0, 0), (b, 0, 0)]);
    expect(none.players.where((p) => p.first), isEmpty, reason: 'a first place of 0 wins nothing');
  });

  testWidgets("this week: the players ranked, boosts kept secret, and only who the challengers portray", (
    tester,
  ) async {
    _phone(tester);
    final controller = await launchedGame(launchDate: firstMonday);
    for (var day = 1; day < 4; day++) {
      await controller.advanceDay();
    }

    await tester.pumpWidget(MaterialApp(home: RankingScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    // The players' view of this week first.
    expect(find.byType(PlayerStatsView), findsOneWidget);
    expect(find.textContaining('Week 1, so far.'), findsOneWidget);
    expect(find.textContaining('wins a trophy worth 3 ★'), findsOneWidget);
    final week = (await controller.playerStats(StatPeriod.week))!;
    final wins = week.stats.firstWhere((s) => s.kind == PlayerStatKind.mostWins);
    expect(find.text(PlayerStatKind.mostWins.description), findsOneWidget);
    for (final placed in wins.players) {
      expect(find.text(placed.player.isYou ? '${placed.player.name} (you)' : placed.player.name), findsOneWidget);
    }
    expect(find.text('${wins.players.first.value} wins'), findsWidgets);
    final firsts = find.byKey(const ValueKey('first-place'));
    expect(firsts, findsNWidgets(wins.players.where((p) => p.first).length));
    expect(
      tester.widgetList<Icon>(firsts).map((i) => i.icon),
      everyElement(Icons.emoji_events_outlined),
      reason: 'not won yet',
    );

    // Boosts are secret this week.
    await tester.tap(find.text('Grand Artist'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Secret until the week is over'), findsOneWidget);
    expect(find.textContaining(' ★'), findsOneWidget, reason: 'only in the trophy line, no values');
    await tester.ensureVisible(find.text('Addict'));
    await tester.tap(find.text('Addict'));
    await tester.pumpAndSettle();
    expect(find.text(PlayerStatKind.busyStreak.description), findsOneWidget);
    // The chips scroll to the categories that don't fit a phone.
    await tester.ensureVisible(find.text('Hurry Crew'));
    await tester.tap(find.text('Hurry Crew'));
    await tester.pumpAndSettle();
    expect(find.text(PlayerStatKind.mostHurried.description), findsOneWidget);
    final hurried = week.stats.firstWhere((s) => s.kind == PlayerStatKind.mostHurried);
    expect(find.text('${hurried.players.first.value} hurries'), findsWidgets);
    await tester.ensureVisible(find.text('Prompt Engineer'));
    await tester.tap(find.text('Prompt Engineer'));
    await tester.pumpAndSettle();
    expect(find.text(PlayerStatKind.mostPrompted.description), findsOneWidget);
    expect(find.textContaining('Secret until the week is over'), findsOneWidget, reason: 'like Grand Artist');

    // The challengers of this week: only who they portray.
    await tester.tap(find.text('Challengers'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayersDashboard), findsOneWidget);
    final total = week.portrayed.fold(0, (sum, p) => sum + p.$2);
    expect(total, greaterThan(0));
    expect(find.textContaining('Week 1, so far: $total challengers drawn for this week'), findsOneWidget);
    expect(find.textContaining('#1'), findsNothing, reason: 'no ranking before the week is over');
    expect(find.byType(CardboardCard), findsNothing, reason: 'nor their drawings');
    expect(find.text('Boost balance'), findsNothing, reason: 'the first week has the base stars');

    // No last week yet, in either view.
    await tester.tap(find.text('Last week'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No ranking yet'), findsOneWidget);
    await tester.tap(find.text('Players'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No ranking yet'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("this week's challengers: the boost stars they're boosted with, and why", (tester) async {
    _phone(tester);
    final controller = await launchedGame(launchDate: firstMonday, day: 8);
    final balance = (await controller.playerStats(StatPeriod.week))!.boostBalance!;
    await tester.pumpWidget(
      MaterialApp(
        home: RankingScreen(controller: controller, view: RankingView.challengers),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    // The rules behind it are in the boost tutorial.
    expect(find.text('Boost balance'), findsOneWidget);
    expect(find.text('${balance.stars} ★ a day'), findsOneWidget);
    expect(
      find.text('Up from ${balance.previousStars} ★ from last week (hero win rate ${balance.heroPercent}%)'),
      findsOneWidget,
      reason: "the mockup's heroes won about three fights in four",
    );
  });

  testWidgets("last week: the players' trophies", (tester) async {
    _phone(tester);
    final controller = await launchedGame(launchDate: firstMonday);
    for (var day = 1; day < 8; day++) {
      await controller.advanceDay();
    }
    await tester.pumpWidget(
      MaterialApp(
        home: RankingScreen(controller: controller, period: StatPeriod.lastWeek),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Week 1. The first place of each category won a trophy worth 3 ★.'), findsOneWidget);
    await tester.tap(find.text('Grand Artist'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Secret'), findsNothing, reason: 'not once the week is over');
    final last = (await controller.playerStats(StatPeriod.lastWeek))!;
    final boosted = last.stats.firstWhere((s) => s.kind == PlayerStatKind.mostBoosted);
    final firsts = boosted.players.where((p) => p.first);
    expect(find.textContaining('+3'), findsNothing, reason: 'no stars in the table');
    final first = find.byKey(const ValueKey('first-place'));
    expect(first, findsNWidgets(firsts.length));
    expect(tester.widgetList<Icon>(first).map((i) => i.icon), everyElement(Icons.emoji_events_rounded), reason: 'won');
    for (final place in [for (final p in boosted.players) '${p.place}']) {
      expect(find.text(place), findsNothing, reason: 'no place numbers');
    }
    final withTrophies = boosted.players.where((p) => p.trophies > 0);
    expect(find.textContaining('×'), findsNWidgets(withTrophies.length));
    for (final placed in withTrophies) {
      expect(find.text('×${placed.trophies}'), findsWidgets);
    }
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("last week's challengers: the heroes first, then the others, each with its details", (tester) async {
    _phone(tester);
    final controller = await launchedGame(launchDate: firstMonday);
    for (var day = 1; day < 8; day++) {
      await controller.advanceDay();
    }
    final ranking = (await controller.weekRanking())!;
    await tester.pumpWidget(
      MaterialApp(
        home: RankingScreen(controller: controller, view: RankingView.challengers, period: StatPeriod.lastWeek),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.textContaining('Week 1: ${ranking.challengers.length} challengers'), findsOneWidget);
    final hero = ranking.challengers.first;
    expect(find.text(hero.card.title), findsWidgets, reason: 'in its nameplate');
    expect(find.text('${hero.stars} ★').first, findsOneWidget);
    expect(find.textContaining('The top 3 became weekly heroes'), findsOneWidget);
    expect(find.text('#1 · Weekly hero · ★★★★'), findsOneWidget, reason: 'the heroes on bigger cards');
    expect(find.text('#2 · Weekly hero · ★★★'), findsOneWidget);
    expect(find.text('#3 · Weekly hero · ★★'), findsOneWidget);
    expect(find.text('${ranking.challengers[3].place}'), findsWidgets, reason: 'the others numbered below');
    expect(find.textContaining('Drawn by'), findsNothing, reason: 'details are on their own screen');

    expect(find.text('Boost balance'), findsNothing, reason: "it's in this week's overview");

    // How often each player was chosen as a challenger, as a pie and a legend.
    expect(find.byType(PlayersDashboard), findsOneWidget);
    final weeks = PlayerWeek.ofRanking(controller.server.players, ranking);
    expect(weeks, hasLength(controller.server.players.length), reason: 'every player in the legend');
    expect(weeks.map((w) => w.chosen).fold(0, (a, b) => a + b), ranking.challengers.length);
    expect([for (final w in weeks) w.chosen], [...weeks.map((w) => w.chosen)]..sort((a, b) => b.compareTo(a)));
    expect(find.text('Chosen as challenger'), findsOneWidget);
    final top = weeks.first;
    expect(find.text('${top.chosen} · ${(100 * top.chosen / ranking.challengers.length).round()}%'), findsWidgets);

    // The refresh button asks again, and keeps the ranking shown.
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('#1 · Weekly hero · ★★★★'), findsOneWidget);

    // The details of the weekly hero.
    await tester.ensureVisible(find.text('#1 · Weekly hero · ★★★★'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#1 · Weekly hero · ★★★★'));
    await tester.pumpAndSettle();
    expect(find.byType(RankingDetailScreen), findsOneWidget);
    expect(find.text('Weekly hero (Legend) with ${hero.stars} ★'), findsOneWidget);
    expect(find.text('Drawn by'), findsOneWidget);
    expect(find.text(hero.card.artist), findsOneWidget);
    // What its place was decided by after its boost stars.
    expect(find.text('Day ${hero.card.day} · ${controller.themeOfDay(hero.card.day).label}'), findsOneWidget);
    expect(find.text("${hero.card.artist}'s challengers this week"), findsOneWidget);
    expect(find.text('+${hero.artistBoostStars} ★ boosted'), findsOneWidget);
    expect(find.text('${hero.winPercent}% · won ${hero.wins} of ${hero.fights}'), findsOneWidget);
    final author = hero.promptAuthor!;
    expect(find.text(hero.defaultPrompt ? '${author.name} (default)' : author.name), findsOneWidget);
    expect(find.text(hero.boostStars == 0 ? 'not boosted' : '+${hero.boostStars} ★'), findsOneWidget);
    for (final boost in hero.boosts) {
      expect(
        find.text('${boost.booster.name}: +${boost.stars} ★${boost.byChance ? ' (default)' : ''}'),
        findsOneWidget,
      );
    }
    final fight = hero.foughtBy.single;
    expect(
      find.text("${fight.challengerWon ? 'Won' : 'Lost'} against ${fight.player.name}'s team of heroes"),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    // Its drawing, full screen.
    await tester.tap(find.byType(CardboardCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenDrawing), findsOneWidget);
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenDrawing), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
