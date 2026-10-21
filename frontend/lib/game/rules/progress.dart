import 'models.dart';
import 'upgrades.dart';

/// How far a player's collection has come, for one rarity or all of them.
class Progress {
  const Progress({
    required this.inPool,
    required this.collected,
    required this.owned,
    required this.maxed,
    required this.unlockedSteps,
    required this.steps,
    required this.duplicatesToMax,
    required this.spareDuplicates,
  });

  /// Characters of the pool, and how many of them you own.
  final int inPool;
  final int collected;

  /// Characters you own, from outside the pool too (challengers pulled
  /// before they left it).
  final int owned;

  /// Owned characters with every upgrade unlocked.
  final int maxed;

  /// Upgrades unlocked on owned characters, out of all their [steps].
  final int unlockedSteps;
  final int steps;

  /// Duplicates still needed to max out every owned character.
  final int duplicatesToMax;

  /// Duplicates not spent on upgrades, maxed out characters' included.
  final int spareDuplicates;

  /// A character of the pool you don't own yet.
  static const _missing = Progress(
    inPool: 1,
    collected: 0,
    owned: 0,
    maxed: 0,
    unlockedSteps: 0,
    steps: 0,
    duplicatesToMax: 0,
    spareDuplicates: 0,
  );

  static const empty = Progress(
    inPool: 0,
    collected: 0,
    owned: 0,
    maxed: 0,
    unlockedSteps: 0,
    steps: 0,
    duplicatesToMax: 0,
    spareDuplicates: 0,
  );

  Progress operator +(Progress other) => Progress(
    inPool: inPool + other.inPool,
    collected: collected + other.collected,
    owned: owned + other.owned,
    maxed: maxed + other.maxed,
    unlockedSteps: unlockedSteps + other.unlockedSteps,
    steps: steps + other.steps,
    duplicatesToMax: duplicatesToMax + other.duplicatesToMax,
    spareDuplicates: spareDuplicates + other.spareDuplicates,
  );

  /// One owned character's progress.
  factory Progress.ofOwned(OwnedCard owned, {required bool inPool}) {
    final locked = [
      for (final (i, effect) in owned.path.indexed)
        if (!owned.unlocked.contains(effect)) owned.costs[i],
    ];
    final points = owned.upgradePoints;
    final toMax = locked.fold(0, (a, b) => a + b) - (points > 0 ? points : 0);
    return Progress(
      inPool: inPool ? 1 : 0,
      collected: inPool ? 1 : 0,
      owned: 1,
      maxed: owned.nextUpgrade == null ? 1 : 0,
      unlockedSteps: owned.path.length - locked.length,
      steps: owned.path.length,
      duplicatesToMax: toMax > 0 ? toMax : 0,
      spareDuplicates: points > 0 ? points : 0,
    );
  }

  /// The progress per rarity of a [collection] in a [pool]; characters you
  /// own from outside the pool count as owned, but not towards the pool.
  static Map<Rarity, Progress> byRarity(List<CharacterCard> pool, List<OwnedCard> collection) {
    final owned = {for (final o in collection) o.card.id: o};
    final poolIds = {for (final card in pool) card.id};
    final result = {for (final rarity in Rarity.values) rarity: Progress.empty};
    for (final card in pool) {
      if (!owned.containsKey(card.id)) result[card.rarity] = result[card.rarity]! + _missing;
    }
    for (final o in collection) {
      result[o.card.rarity] = result[o.card.rarity]! + Progress.ofOwned(o, inPool: poolIds.contains(o.card.id));
    }
    return result;
  }
}
