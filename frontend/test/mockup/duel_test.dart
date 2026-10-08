import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/mockup/logic/duel.dart';
import 'package:frontend/mockup/logic/models.dart';

void main() {
  test('upgrades and rarity make fighters stronger', () {
    expect(FighterStats.of(Rarity.legend).attack, greaterThan(FighterStats.of(Rarity.basic).attack));
    expect(FighterStats.of(Rarity.basic, upgrades: 2).attack, greaterThan(FighterStats.of(Rarity.basic).attack));
  });

  test('duels end and report a consistent winner', () {
    for (var seed = 0; seed < 100; seed++) {
      final result = Duel.simulate(
        FighterStats.of(Rarity.adventurer),
        FighterStats.of(Rarity.hero),
        random: Random(seed),
      );
      expect(result.hits, isNotEmpty);
      expect(result.hits.length, lessThanOrEqualTo(Duel.maxRounds));
      final last = result.hits.last;
      if (last.rightHp == 0) expect(result.leftWins, isTrue);
      if (last.leftHp == 0) expect(result.leftWins, isFalse);
    }
  });

  test('stronger fighters win more often', () {
    var wins = 0;
    for (var seed = 0; seed < 500; seed++) {
      if (Duel.simulate(FighterStats.of(Rarity.legend), FighterStats.of(Rarity.basic), random: Random(seed)).leftWins) {
        wins++;
      }
    }
    expect(wins, greaterThan(400));
  });
}
