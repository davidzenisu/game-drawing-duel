import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/ranking_screen.dart';

import '../helpers.dart';

void main() {
  testWidgets('the week ranking lists every challenger, the hero first', (tester) async {
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
    expect(find.text('${hero.card.subject} · ${hero.card.title}'), findsWidgets);
    expect(find.textContaining('Weekly hero'), findsOneWidget);
    expect(find.text('${hero.stars} ★').first, findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'places are numbered');
    await tester.pumpWidget(const SizedBox());
  });
}
