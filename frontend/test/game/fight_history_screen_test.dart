import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/fight_history_screen.dart';
import 'package:frontend/game/screens/fight_replay_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

/// A mockup game on day 8 where you drew a challenger on day 5 and fought on
/// day 7: both fights were on day 7.
Future<MockGameSession> _foughtOnDaySeven() async {
  final game = await launchedGame(launchDate: firstMonday, day: 5);
  await game.submitChallenger(doodle);
  await game.advanceDay();
  await game.advanceDay();
  await game.submitFighters(game.availableFighters.take(1).toList());
  await game.advanceDay();
  return game;
}

void main() {
  test('the days before today have their fights, one per challenger', () async {
    final game = await _foughtOnDaySeven();
    final days = await game.fightDays();
    expect([for (final d in days) d.day], [7, 6, 5, 4], reason: 'newest first, from the first fights');
    expect(fightDate(days.first.date), 'Sunday, 11 October 2026');

    final fights = await game.fightsOn(7);
    expect({for (final f in fights) f.challenger.id}.length, fights.length, reason: 'every challenger once');
    expect(fights.where((f) => f.owner.isYou).single.id, 'fight7-${game.you.id}', reason: 'your own fight');
    final drawn = fights.singleWhere((f) => f.challenger.artist == game.you.name);
    expect(drawn.owner.isYou, isFalse, reason: 'a friend fought yours');
    for (final f in fights.where((f) => !f.owner.isYou)) {
      // Like the ranking: the challengers drawn on even days won theirs.
      expect(f.fightersWin, f.challenger.day.isOdd, reason: f.challenger.id);
      expect(f.owner.name, isNot(f.challenger.artist), reason: 'nobody fights their own');
    }
    expect(await game.fightsOn(8), isEmpty, reason: "not today's");
  });

  test('without your drawing, everyone still fights: one challenger twice', () async {
    final game = await launchedGame(launchDate: firstMonday, day: 8);
    final fights = await game.fightsOn(7);
    final challengers = {for (final f in fights) f.challenger.id};
    expect((fights.length, challengers.length), (5, 4), reason: '4 friends drew; they and you fight');
    expect({for (final f in fights) f.owner.id}.length, 5, reason: 'one fight each');
    expect(fights.where((f) => f.challenger.artist == game.you.name), isEmpty);
    for (final f in fights) {
      expect(f.owner.name, isNot(f.challenger.artist), reason: 'nobody fights their own');
    }
  });

  testWidgets('pick a day, then a challenger to replay its fight', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await _foughtOnDaySeven();
    await tester.pumpWidget(MaterialApp(home: FightHistoryScreen(controller: game)));
    await tester.pumpAndSettle();
    expect(find.text('Day 7'), findsOneWidget);
    expect(find.text('Sunday, 11 October 2026'), findsOneWidget);
    expect(find.text('Day 4'), findsOneWidget);

    await tester.tap(find.text('Day 7'));
    await tester.pumpAndSettle();
    expect(find.byType(DayFightsScreen), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    // Yours come first and stand out.
    Offset tile(String mark) =>
        tester.getTopLeft(find.ancestor(of: find.text(mark), matching: find.byType(Card)).first);
    expect(tile('You fought it').dy, tile('You drew it').dy, reason: 'side by side, first');
    expect(tile('You fought it').dx, lessThan(tile('You drew it').dx));

    await tester.tap(find.text('You fought it'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FightReplayScreen), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
