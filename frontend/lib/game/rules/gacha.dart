import 'dart:math';

import 'models.dart';

/// Pity progress shown to the player.
class GachaStatus {
  const GachaStatus({required this.totalPulls, required this.pullsUntilLegend, required this.beginnerPullsLeft});

  final int totalPulls;

  /// Pulls left until a legend is guaranteed.
  final int pullsUntilLegend;

  /// Pulls left within the beginner window, or `null` once it no longer applies.
  final int? beginnerPullsLeft;
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

  /// Within the first pulls a 3 or 4 star character is guaranteed.
  static const beginnerWindow = 10;

  /// Every this many pulls without a legend, the next one is a legend.
  static const legendPity = 50;

  /// A pull landing on a rarity with rate-up characters picks one of them
  /// this often (percent), as long as the rarity has others too.
  static const rateUp = 50;

  final Random _random;

  int _totalPulls = 0;
  int _pullsSinceLegend = 0;
  bool _beginnerGuaranteeMet = false;

  int get totalPulls => _totalPulls;

  /// Pulls left until a legend is guaranteed.
  int get pullsUntilLegend => legendPity - _pullsSinceLegend;

  /// Pulls left within the beginner window, or `null` once it no longer applies.
  int? get beginnerPullsLeft =>
      _beginnerGuaranteeMet || _totalPulls >= beginnerWindow ? null : beginnerWindow - _totalPulls;

  GachaStatus get status =>
      GachaStatus(totalPulls: totalPulls, pullsUntilLegend: pullsUntilLegend, beginnerPullsLeft: beginnerPullsLeft);

  /// Pulls a character from [pool], which must not be empty; the ids in
  /// [rateUp] are this week's rate-up characters.
  CharacterCard pull(List<CharacterCard> pool, {Set<String> rateUp = const {}}) {
    if (pool.isEmpty) throw StateError('The pool is empty.');

    final (rarity, guaranteed) = _rollRarity();
    final tier = closestAvailableTier({for (final card in pool) card.rarity}, rarity, preferHigher: guaranteed);
    final card = pickCharacter(pool.where((card) => card.rarity == tier).toList(), rateUp, _random);

    _totalPulls++;
    _pullsSinceLegend = card.rarity == Rarity.legend ? 0 : _pullsSinceLegend + 1;
    if (card.rarity.stars >= Rarity.hero.stars) _beginnerGuaranteeMet = true;
    return card;
  }

  (Rarity, bool) _rollRarity() {
    if (_pullsSinceLegend + 1 >= legendPity) return (Rarity.legend, true);
    if (!_beginnerGuaranteeMet && _totalPulls == beginnerWindow - 1) {
      final heroWeight = rates[Rarity.hero]!;
      final roll = _random.nextInt(heroWeight + rates[Rarity.legend]!);
      return (roll < heroWeight ? Rarity.hero : Rarity.legend, true);
    }
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
