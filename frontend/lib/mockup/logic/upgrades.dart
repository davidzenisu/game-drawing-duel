import 'models.dart';

/// Special effects unlocked by spending duplicates, see `docs/concept/features.md`.
enum UpgradeEffect {
  shadow('Shadow', 'A dramatic drop shadow.'),
  light('Light', 'A soft glow behind the card.'),
  element('Element', 'An elemental aura of your choice.'),
  aura('Aura', 'The elemental aura grows stronger.'),
  halo('Halo', 'A shining halo only legends can earn.');

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

  /// Every duplicate is worth one upgrade point.
  int get upgradePoints => copies - 1 - unlocked.length;

  List<UpgradeEffect> get path => UpgradeTree.pathFor(card.rarity);

  UpgradeEffect? get nextUpgrade => unlocked.length < path.length ? path[unlocked.length] : null;

  bool get canUpgrade => upgradePoints > 0 && nextUpgrade != null;

  bool has(UpgradeEffect effect) => unlocked.contains(effect);
}
