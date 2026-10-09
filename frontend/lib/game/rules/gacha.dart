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

  /// Pulls a character from [pool], which must not be empty.
  CharacterCard pull(List<CharacterCard> pool) {
    if (pool.isEmpty) throw StateError('The pool is empty.');

    final (rarity, guaranteed) = _rollRarity();
    final tier = closestAvailableTier({for (final card in pool) card.rarity}, rarity, preferHigher: guaranteed);
    final candidates = pool.where((card) => card.rarity == tier).toList();
    final card = candidates[_random.nextInt(candidates.length)];

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
