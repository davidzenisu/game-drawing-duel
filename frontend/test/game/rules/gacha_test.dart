import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/rules/models.dart';

List<CharacterCard> poolOf(Map<Rarity, int> counts) => [
  for (final MapEntry(key: rarity, value: count) in counts.entries)
    for (var i = 0; i < count; i++)
      CharacterCard(
        id: '${rarity.name}$i',
        subject: 'S$i',
        title: 'T',
        rarity: rarity,
        prompt: rarity.label,
        artist: 'A',
        sketch: Sketch.empty,
      ),
];

void main() {
  final pool = poolOf({Rarity.basic: 10, Rarity.adventurer: 10, Rarity.hero: 5, Rarity.legend: 5});

  test('rates add up to 100%', () {
    expect(GachaMachine.rates.values.reduce((a, b) => a + b), 100);
  });

  test('the first 10 pulls always contain a 3 or 4 star', () {
    for (var seed = 0; seed < 200; seed++) {
      final gacha = GachaMachine(random: Random(seed));
      final pulls = [for (var i = 0; i < GachaMachine.beginnerWindow; i++) gacha.pull(pool)];
      expect(pulls.any((c) => c.rarity.stars >= 3), isTrue, reason: 'seed $seed');
    }
  });

  test('a legend is guaranteed at least every 50 pulls', () {
    for (var seed = 0; seed < 50; seed++) {
      final gacha = GachaMachine(random: Random(seed));
      var sinceLegend = 0;
      for (var i = 0; i < 300; i++) {
        sinceLegend = gacha.pull(pool).rarity == Rarity.legend ? 0 : sinceLegend + 1;
        expect(sinceLegend, lessThan(GachaMachine.legendPity), reason: 'seed $seed, pull $i');
      }
    }
  });

  test('missing tiers fall back to the nearest available one', () {
    final basicsOnly = poolOf({Rarity.basic: 3});
    final gacha = GachaMachine(random: Random(1));
    for (var i = 0; i < 60; i++) {
      expect(gacha.pull(basicsOnly).rarity, Rarity.basic);
    }

    final noHeroes = poolOf({Rarity.basic: 3, Rarity.legend: 1});
    final beginner = GachaMachine(random: Random(2));
    final pulls = [for (var i = 0; i < GachaMachine.beginnerWindow; i++) beginner.pull(noHeroes)];
    expect(pulls.any((c) => c.rarity == Rarity.legend), isTrue, reason: 'guaranteed pulls look upwards');
  });

  test('counters are reported for the UI', () {
    final gacha = GachaMachine(random: Random(3));
    expect(gacha.beginnerPullsLeft, GachaMachine.beginnerWindow);
    expect(gacha.pullsUntilLegend, GachaMachine.legendPity);
    gacha.pull(poolOf({Rarity.basic: 1}));
    expect(gacha.totalPulls, 1);
    expect(gacha.beginnerPullsLeft, GachaMachine.beginnerWindow - 1);
    expect(gacha.pullsUntilLegend, GachaMachine.legendPity - 1);
  });
}
