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

  test('a rarity without characters passes its rate on to the tier pulled instead', () {
    expect(GachaMachine.tierRates(Rarity.values.toSet()), GachaMachine.rates);
    // No basics: their share goes up to the adventurers.
    expect(GachaMachine.tierRates({Rarity.adventurer, Rarity.hero, Rarity.legend}), {
      Rarity.adventurer: 90,
      Rarity.hero: 8,
      Rarity.legend: 2,
    });
    // No legends: theirs goes down to the heroes.
    expect(GachaMachine.tierRates({Rarity.basic, Rarity.adventurer, Rarity.hero}), {
      Rarity.basic: 40,
      Rarity.adventurer: 50,
      Rarity.hero: 10,
    });
    expect(GachaMachine.tierRates({}), isEmpty);
  });

  group('rate up', () {
    final heroes = poolOf({Rarity.hero: 4});
    final hero = heroes.first;

    Map<String, int> picks(List<CharacterCard> candidates, Set<String> rateUp) {
      final random = Random(7);
      final counts = <String, int>{};
      for (var i = 0; i < 20000; i++) {
        final id = GachaMachine.pickCharacter(candidates, rateUp, random).id;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      return counts;
    }

    test('a featured character gets half of its rarity', () {
      final counts = picks(heroes, {hero.id});
      expect(counts[hero.id]! / 20000, closeTo(GachaMachine.rateUp / 100, 0.02));
      for (final other in heroes.skip(1)) {
        expect(counts[other.id]! / 20000, closeTo(0.5 / 3, 0.02));
      }
    });

    test('alone in its rarity, it is every pull', () {
      expect(picks([hero], {hero.id}), {hero.id: 20000});
    });

    test('the chances shown split the same way and add up to 100%', () {
      final pool = poolOf({Rarity.basic: 5, Rarity.adventurer: 5, Rarity.hero: 4, Rarity.legend: 2});
      final legend = pool.lastWhere((c) => c.rarity == Rarity.legend);
      final chances = GachaMachine.characterChances(pool, {hero.id, legend.id});
      expect(chances.values.reduce((a, b) => a + b), closeTo(100, 1e-9));
      expect(chances[hero.id], closeTo(8 * 0.5, 1e-9));
      expect(
        chances[pool.firstWhere((c) => c.rarity == Rarity.hero && c.id != hero.id).id],
        closeTo(8 * 0.5 / 3, 1e-9),
      );
      expect(chances[legend.id], closeTo(2 * 0.5, 1e-9));
      expect(chances[pool.first.id], closeTo(40 / 5, 1e-9));
      // Nothing rate-up: everyone in a rarity alike.
      expect(GachaMachine.characterChances(pool, {})[hero.id], closeTo(8 / 4, 1e-9));
    });
  });

  test('pulls follow the tier rates', () {
    // No basics; legends stay in, so their pity resets as usual.
    final noBasics = poolOf({Rarity.adventurer: 10, Rarity.hero: 5, Rarity.legend: 5});
    final rates = GachaMachine.tierRates({Rarity.adventurer, Rarity.hero, Rarity.legend});
    final gacha = GachaMachine(random: Random(1));
    final counts = <Rarity, int>{};
    for (var i = 0; i < 20000; i++) {
      final rarity = gacha.pull(noBasics).rarity;
      counts[rarity] = (counts[rarity] ?? 0) + 1;
    }
    for (final MapEntry(key: rarity, value: rate) in rates.entries) {
      // Pity adds a little on top of the legends' 2%.
      expect(counts[rarity]! / 200, closeTo(rate, 1.5), reason: rarity.label);
    }
  });

  test('the first 10 standard pulls always contain a legend', () {
    for (var seed = 0; seed < 200; seed++) {
      final gacha = GachaMachine(random: Random(seed));
      // Weekly pulls in between don't count towards the window.
      gacha.pull(pool, banner: GachaBanner.weekly);
      final pulls = [for (var i = 0; i < GachaMachine.beginnerWindow; i++) gacha.pull(pool)];
      expect(pulls.any((c) => c.rarity == Rarity.legend), isTrue, reason: 'seed $seed');
      expect(gacha.beginnerPullsLeft, isNull);
    }
  });

  test('the beginner guarantee is only on the standard banner', () {
    var withLegend = 0;
    for (var seed = 0; seed < 200; seed++) {
      final gacha = GachaMachine(random: Random(seed));
      final pulls = [
        for (var i = 0; i < GachaMachine.beginnerWindow; i++) gacha.pull(pool, banner: GachaBanner.weekly),
      ];
      if (pulls.any((c) => c.rarity == Rarity.legend)) withLegend++;
      expect(gacha.beginnerPullsLeft, GachaMachine.beginnerWindow, reason: 'still waiting for standard pulls');
    }
    // About 18% of 10 pulls at 2% each.
    expect(withLegend, lessThan(80));
  });

  test('the legend pity counts both banners', () {
    final gacha = GachaMachine(random: Random(5));
    final basics = poolOf({Rarity.basic: 3});
    for (var i = 0; i < 20; i++) {
      gacha.pull(basics, banner: i.isEven ? GachaBanner.standard : GachaBanner.weekly);
    }
    expect(gacha.pullsUntilLegend, GachaMachine.legendPity - 20);
  });

  test('the standard banner pulls only the setup drawings, without rate-up', () {
    final setup = poolOf({Rarity.basic: 2, Rarity.legend: 2});
    final weeklyHero = CharacterCard(
      id: 'weekly',
      subject: 'S0',
      title: 'T',
      rarity: Rarity.hero,
      prompt: 'Challenger',
      artist: 'A',
      sketch: Sketch.empty,
      day: 7,
    );
    final all = [...setup, weeklyHero];
    expect(GachaBanner.standard.poolOf(all), setup);
    expect(GachaBanner.weekly.poolOf(all), all);
    final gacha = GachaMachine(random: Random(6));
    final pulled = {
      for (var i = 0; i < 500; i++) gacha.pull(all, rateUp: {'legend0'}).id,
    };
    expect(pulled, isNot(contains('weekly')));
    final legends = [
      for (var i = 0; i < 4000; i++) gacha.pull(setup, rateUp: {'legend0'}),
    ].where((c) => c.rarity == Rarity.legend);
    expect(legends.where((c) => c.id == 'legend0').length / legends.length, closeTo(0.5, 0.15));
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

    final noLegends = poolOf({Rarity.basic: 3, Rarity.hero: 1});
    final beginner = GachaMachine(random: Random(2));
    final pulls = [for (var i = 0; i < GachaMachine.beginnerWindow; i++) beginner.pull(noLegends)];
    expect(pulls.any((c) => c.rarity == Rarity.hero), isTrue, reason: 'guaranteed pulls take the nearest tier');
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
