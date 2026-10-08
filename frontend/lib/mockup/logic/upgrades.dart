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
}

/// A character in the player's collection.
class OwnedCard {
  OwnedCard(this.card);

  final CharacterCard card;
  int copies = 1;
  final List<UpgradeEffect> unlocked = [];
  ElementKind? element;

  /// Every duplicate is worth one upgrade point. The mockup lets players
  /// unlock upgrades on credit, so this can go negative.
  int get upgradePoints => copies - 1 - unlocked.length;

  List<UpgradeEffect> get path => UpgradeTree.pathFor(card.rarity);

  UpgradeEffect? get nextUpgrade => unlocked.length < path.length ? path[unlocked.length] : null;

  bool get canUpgrade => nextUpgrade != null;

  /// Whether a duplicate is waiting to be spent.
  bool get hasUnspentPoints => upgradePoints > 0 && nextUpgrade != null;

  bool has(UpgradeEffect effect) => unlocked.contains(effect);
}
