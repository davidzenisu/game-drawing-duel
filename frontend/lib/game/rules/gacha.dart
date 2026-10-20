import 'dart:math';

import 'models.dart';

/// Pity progress shown to the player.
class GachaStatus {
  const GachaStatus({required this.totalPulls, required this.pullsUntilLegend, required this.beginnerPullsLeft});

  final int totalPulls;

  /// Pulls left until a legend is guaranteed.
  final int pullsUntilLegend;

  /// Standard banner pulls left within the beginner window, or `null` once
  /// it no longer applies.
  final int? beginnerPullsLeft;
}

/// What a pull draws from, like the server's `Banner` (`backend/app/gacha.py`).
enum GachaBanner {
  /// Always there: the setup drawings, with a legend guaranteed within the
  /// first pulls on it.
  standard('Standard'),

  /// From the first finale on: the whole pool, weekly heroes included, with
  /// this week's rate-up.
  weekly('Weekly');

  const GachaBanner(this.label);

  final String label;

  /// The characters of [pool] this banner pulls from.
  List<CharacterCard> poolOf(List<CharacterCard> pool) => switch (this) {
    // The setup drawings are the ones in the pool from day 0.
    standard => [
      for (final card in pool)
        if (card.day == 0) card,
    ],
    weekly => pool,
  };
}

/// Gacha pulls with rates and pity, see `docs/concept/gacha-rates.md`.
///
/// The server pulls the same way (`backend/app/gacha.py`); both are checked
/// against `shared/rules.json`.
class GachaMachine {
  GachaMachine({Random? random}) : _random = random ?? Random();

  /// Pulls every player receives when a server launches.
  static const launchBonus = 10;

  /// Pull chances in percent.
  static const rates = {Rarity.basic: 40, Rarity.adventurer: 50, Rarity.hero: 8, Rarity.legend: 2};

  /// Within the first pulls on the standard banner, a legend is guaranteed
  /// once.
  static const beginnerWindow = 10;

  /// Every this many pulls without a legend, the next one is a legend.
  static const legendPity = 50;

  /// A pull landing on a rarity with rate-up characters picks one of them
  /// this often (percent), as long as the rarity has others too.
  static const rateUp = 50;

  final Random _random;

  int _totalPulls = 0;

  /// The legend pity counts the pulls on every banner.
  int _pullsSinceLegend = 0;

  /// The beginner guarantee only the ones on the standard banner.
  int _standardPulls = 0;
  bool _beginnerGuaranteeMet = false;

  int get totalPulls => _totalPulls;

  /// Pulls left until a legend is guaranteed.
  int get pullsUntilLegend => legendPity - _pullsSinceLegend;

  /// Standard banner pulls left within the beginner window, or `null` once
  /// it no longer applies.
  int? get beginnerPullsLeft =>
      _beginnerGuaranteeMet || _standardPulls >= beginnerWindow ? null : beginnerWindow - _standardPulls;

  GachaStatus get status =>
      GachaStatus(totalPulls: totalPulls, pullsUntilLegend: pullsUntilLegend, beginnerPullsLeft: beginnerPullsLeft);

  /// Pulls a character on [banner] from [pool], the whole pool; the ids in
  /// [rateUp] are this week's rate-up characters on the weekly banner.
  CharacterCard pull(
    List<CharacterCard> pool, {
    GachaBanner banner = GachaBanner.standard,
    Set<String> rateUp = const {},
  }) {
    final candidates = banner.poolOf(pool);
    if (candidates.isEmpty) throw StateError('The pool is empty.');

    final (rarity, guaranteed) = _rollRarity(banner);
    final tier = closestAvailableTier({for (final card in candidates) card.rarity}, rarity, preferHigher: guaranteed);
    final card = pickCharacter(
      candidates.where((card) => card.rarity == tier).toList(),
      banner == GachaBanner.weekly ? rateUp : const {},
      _random,
    );

    _totalPulls++;
    _pullsSinceLegend = card.rarity == Rarity.legend ? 0 : _pullsSinceLegend + 1;
    if (banner == GachaBanner.standard) {
      _standardPulls++;
      if (card.rarity == Rarity.legend) _beginnerGuaranteeMet = true;
    }
    return card;
  }

  (Rarity, bool) _rollRarity(GachaBanner banner) {
    if (_pullsSinceLegend + 1 >= legendPity) return (Rarity.legend, true);
    if (banner == GachaBanner.standard && beginnerPullsLeft == 1) return (Rarity.legend, true);
    var roll = _random.nextInt(rates.values.reduce((a, b) => a + b));
    for (final MapEntry(key: rarity, value: weight) in rates.entries) {
      if (roll < weight) return (rarity, false);
      roll -= weight;
    }
    return (Rarity.basic, false);
  }

  /// One of a rarity's [candidates], all equally likely, except that the
  /// [rateUp] ones share [GachaMachine.rateUp] percent of the rarity when it
  /// has others.
  static CharacterCard pickCharacter(List<CharacterCard> candidates, Set<String> rateUp, Random random) {
    final featured = [
      for (final card in candidates)
        if (rateUp.contains(card.id)) card,
    ];
    final others = [
      for (final card in candidates)
        if (!rateUp.contains(card.id)) card,
    ];
    final from = featured.isNotEmpty && others.isNotEmpty
        ? (random.nextInt(100) < GachaMachine.rateUp ? featured : others)
        : candidates;
    return from[random.nextInt(from.length)];
  }

  /// Each character's chance in percent, before guarantees, by id: its
  /// rarity's share of [tierRates], split as [pickCharacter] picks.
  static Map<String, double> characterChances(List<CharacterCard> pool, Set<String> rateUp) {
    final chances = <String, double>{};
    for (final MapEntry(key: rarity, value: rate) in tierRates({for (final card in pool) card.rarity}).entries) {
      final tier = [
        for (final card in pool)
          if (card.rarity == rarity) card,
      ];
      final featured = tier.where((card) => rateUp.contains(card.id)).length;
      final others = tier.length - featured;
      for (final card in tier) {
        chances[card.id] = featured == 0 || others == 0
            ? rate / tier.length
            : rateUp.contains(card.id)
            ? rate * GachaMachine.rateUp / 100 / featured
            : rate * (100 - GachaMachine.rateUp) / 100 / others;
      }
    }
    return chances;
  }

  /// Each rarity's chance in percent, before guarantees, for a pool with
  /// characters of the [available] rarities: one without characters passes
  /// its rate on to the tier a pull would take instead.
  static Map<Rarity, int> tierRates(Set<Rarity> available) {
    if (available.isEmpty) return const {};
    final result = <Rarity, int>{};
    for (final MapEntry(key: rarity, value: rate) in rates.entries) {
      final tier = closestAvailableTier(available, rarity, preferHigher: false);
      result[tier] = (result[tier] ?? 0) + rate;
    }
    return result;
  }

  /// The tier to pull from when [wanted] has no characters: the nearest
  /// [available] one. Guaranteed pulls look upwards first so pity never hands
  /// out something worse.
  static Rarity closestAvailableTier(Set<Rarity> available, Rarity wanted, {required bool preferHigher}) {
    if (available.contains(wanted)) return wanted;
    final higher = Rarity.values.where((r) => r.stars > wanted.stars && available.contains(r));
    final lower = Rarity.values.reversed.where((r) => r.stars < wanted.stars && available.contains(r));
    final order = preferHigher ? [...higher, ...lower] : [...lower, ...higher];
    return order.first;
  }
}
