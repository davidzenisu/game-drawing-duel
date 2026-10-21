import 'models.dart';

/// Special effects unlocked by spending duplicates, see `docs/concept/features.md`.
enum UpgradeEffect {
  shadow('Shadow', 'The ink casts a shadow onto the card.'),
  light('Light', 'The brush strokes start to glow.'),
  element('Element', 'The strokes burn, freeze or crackle with lightning.'),
  aura('Aura', 'Energy surges along every stroke, the element grows wilder.'),
  halo('Halo', 'A golden shimmer, sparkles and a halo. Legends only.');

  const UpgradeEffect(this.label, this.description);

  final String label;
  final String description;
}

enum ElementKind { fire, ice, storm }

/// Each rarity has its own (deeper) upgrade path.
abstract final class UpgradeTree {
  static List<UpgradeEffect> pathFor(Rarity rarity) => switch (rarity) {
    Rarity.basic => const [UpgradeEffect.shadow, UpgradeEffect.light],
    Rarity.adventurer => const [UpgradeEffect.shadow, UpgradeEffect.light, UpgradeEffect.element],
    Rarity.hero => const [UpgradeEffect.shadow, UpgradeEffect.light, UpgradeEffect.element, UpgradeEffect.aura],
    Rarity.legend => UpgradeEffect.values,
  };

  /// How many duplicates each step of a rarity's path costs: more with every
  /// step, and the common rarities take far more to max out.
  static List<int> costsFor(Rarity rarity) => switch (rarity) {
    Rarity.basic => const [10, 20],
    Rarity.adventurer => const [5, 10, 15],
    Rarity.hero => const [1, 2, 3, 4],
    Rarity.legend => const [1, 1, 2, 2, 3],
  };
}

/// A character in the player's collection.
class OwnedCard {
  OwnedCard(this.card);

  final CharacterCard card;
  int copies = 1;
  final List<UpgradeEffect> unlocked = [];
  ElementKind? element;

  /// The duplicates not spent on upgrades yet. The mockup lets players
  /// unlock upgrades on credit, so this can go negative there.
  int get upgradePoints => copies - 1 - costs.take(unlocked.length).fold(0, (a, b) => a + b);

  List<UpgradeEffect> get path => UpgradeTree.pathFor(card.rarity);

  /// What each step of [path] costs, in duplicates.
  List<int> get costs => UpgradeTree.costsFor(card.rarity);

  UpgradeEffect? get nextUpgrade => unlocked.length < path.length ? path[unlocked.length] : null;

  /// The duplicates the next upgrade costs, or `null` once maxed out.
  int? get nextUpgradeCost => nextUpgrade == null ? null : costs[unlocked.length];

  /// Whether the next upgrade can be unlocked, with enough duplicates or,
  /// [onCredit], without.
  bool canUpgrade({bool onCredit = false}) => nextUpgrade != null && (onCredit || upgradePoints >= nextUpgradeCost!);

  /// Whether there are enough duplicates for the next upgrade.
  bool get hasUnspentPoints => canUpgrade();

  bool has(UpgradeEffect effect) => unlocked.contains(effect);
}
