import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/achievements.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/mockup/mock_game_session.dart';

import '../helpers.dart';

/// Summons, with a gift of pulls, until a reward is reached.
Future<void> summonUntilReached(MockGameSession game) async {
  await game.sendGift(message: 'Pulls', pulls: 200);
  await game.acceptGift(game.gifts.last);
  while (game.achievementsToCollect == 0) {
    await game.pull(1);
  }
}

void main() {
  test('the mockup rewards collecting starter heroes and winning fights, once each', () async {
    final game = await launchedGame(launchDate: firstMonday);
    final keys = game.achievements.map((a) => a.key);
    expect(keys.where((k) => k.startsWith('artist:')), hasLength(game.server.players.length - 1));
    expect(keys, containsAll(['wins:1', 'wins:50', 'streak:1', 'streak:25', 'close:1', 'close:50']));

    await summonUntilReached(game);
    final reached = game.achievements.firstWhere((a) => a.collectable);
    final before = game.stars;
    await game.collectAchievement(reached);
    expect(game.stars, before + reached.stars);
    expect(game.achievements.firstWhere((a) => a.key == reached.key).collected, isTrue);
    await game.collectAchievement(reached);
    expect(game.stars, before + reached.stars, reason: 'only once');

    // Win a fight.
    for (var day = 1; day < LoopStep.fight; day++) {
      await game.advanceDay();
    }
    expect(game.achievements.firstWhere((a) => a.key == 'wins:1').progress, 0);
    await game.submitFighters(game.availableFighters.take(4).toList());
    expect(game.achievements.firstWhere((a) => a.key == 'wins:1').done, game.yourFight!.fightersWin);
  });

  test('every achievement reads well', () {
    const threeWins = Achievement(key: 'wins:3', kind: AchievementKind.wins, goal: 3, progress: 1, stars: 5);
    expect((threeWins.title, threeWins.description), ('3 wins', 'Win 3 fights you picked the fighters for.'));
    const closeCall = Achievement(key: 'close:1', kind: AchievementKind.close, goal: 1, progress: 0, stars: 5);
    expect(closeCall.title, 'Close Call');
    expect(closeCall.description, 'Win a fight you picked the fighters for by exactly one star, like 9 against 8.');
    const closeCalls = Achievement(key: 'close:3', kind: AchievementKind.close, goal: 3, progress: 0, stars: 5);
    expect(closeCalls.title, '3 Close Calls');
    const streak = Achievement(key: 'streak:1', kind: AchievementKind.streak, goal: 1, progress: 0, stars: 5);
    expect(streak.title, 'Start a streak');
  });
}
