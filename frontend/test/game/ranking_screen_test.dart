import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/ranking_detail_screen.dart';
import 'package:frontend/game/screens/ranking_screen.dart';
import 'package:frontend/game/widgets/card_art.dart';

import '../helpers.dart';

void main() {
  testWidgets('the week ranking lists every challenger, the hero first, each with its details', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await launchedGame(launchDate: firstMonday);

    await tester.pumpWidget(MaterialApp(home: RankingScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No ranking yet'), findsOneWidget);

    for (var day = 1; day < 8; day++) {
      await controller.advanceDay();
    }
    final ranking = (await controller.weekRanking())!;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: RankingScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    expect(find.textContaining('${ranking.challengers.length} challengers'), findsOneWidget);
    final hero = ranking.challengers.first;
    expect(find.text(hero.card.title), findsWidgets, reason: 'in its nameplate');
    expect(find.text('${hero.stars} ★').first, findsOneWidget);
    expect(find.text('#1 · Weekly hero'), findsOneWidget, reason: 'the winner on a bigger card');
    expect(find.text('2'), findsOneWidget, reason: 'the others numbered below');
    expect(find.textContaining('Drawn by'), findsNothing, reason: 'details are on their own screen');

    // How often each player was chosen as a challenger, as a pie and a legend.
    expect(find.byType(PlayersDashboard), findsOneWidget);
    final weeks = PlayerWeek.of(controller.server.players, ranking);
    expect(weeks, hasLength(controller.server.players.length), reason: 'every player in the legend');
    expect(weeks.map((w) => w.chosen).fold(0, (a, b) => a + b), ranking.challengers.length);
    expect([for (final w in weeks) w.chosen], [...weeks.map((w) => w.chosen)]..sort((a, b) => b.compareTo(a)));
    expect(find.text('Chosen as challenger'), findsOneWidget);
    final top = weeks.first;
    expect(find.text('${top.chosen} · ${(100 * top.chosen / ranking.challengers.length).round()}%'), findsWidgets);

    // The refresh button asks again, and keeps the ranking shown.
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('#1 · Weekly hero'), findsOneWidget);

    // The details of the weekly hero.
    await tester.tap(find.text('#1 · Weekly hero'));
    await tester.pumpAndSettle();
    expect(find.byType(RankingDetailScreen), findsOneWidget);
    expect(find.text('Weekly hero with ${hero.stars} ★'), findsOneWidget);
    expect(find.text('Drawn by'), findsOneWidget);
    expect(find.text(hero.card.artist), findsOneWidget);
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
