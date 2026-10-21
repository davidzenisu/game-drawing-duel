import 'models.dart';

/// Special effects unlocked by spending duplicates, see `docs/concept/features.md`.
enum UpgradeEffect {
  shadow('Shadow', 'The ink casts a shadow onto the card.'),
  outline('Outline', 'A bright sticker outline makes the drawing pop.'),
  light('Light', 'The brush strokes start to glow.'),
  element('Element', 'The strokes burn, freeze or crackle with lightning. From 2 stars.'),
  aura('Aura', 'Energy surges along every stroke, the element grows wilder. From 3 stars.'),
  glitter('Glitter', 'Sparkles twinkle along the lines.'),
  echo('Echo', 'Glowing afterimages trail the drawing.'),
  alive('Alive', 'The drawing breathes and sways on its card.'),
  halo('Halo', 'A golden shimmer, sparkles and a halo. Legends only.');

  const UpgradeEffect(this.label, this.description);

  final String label;
  final String description;
}

enum ElementKind { fire, ice, storm }

/// Each rarity has its own (deeper) upgrade path: the effects every rarity
/// gets, plus the element from 2 stars, the aura from 3 and the halo for
/// legends, in the order they're declared in.
abstract final class UpgradeTree {
  static const _everyone = {
    UpgradeEffect.shadow,
    UpgradeEffect.outline,
    UpgradeEffect.light,
    UpgradeEffect.glitter,
    UpgradeEffect.echo,
    UpgradeEffect.alive,
  };

  static List<UpgradeEffect> pathFor(Rarity rarity) {
    final extra = switch (rarity) {
      Rarity.basic => const <UpgradeEffect>{},
      Rarity.adventurer => const {UpgradeEffect.element},
      Rarity.hero => const {UpgradeEffect.element, UpgradeEffect.aura},
      Rarity.legend => const {UpgradeEffect.element, UpgradeEffect.aura, UpgradeEffect.halo},
    };
    return [
      for (final effect in UpgradeEffect.values)
        if (_everyone.contains(effect) || extra.contains(effect)) effect,
    ];
  }

  /// How many duplicates each step of a rarity's path costs: never less than
  /// the step before, and the common rarities, pulled most, take about 30 to
  /// max out.
  static List<int> costsFor(Rarity rarity) => switch (rarity) {
    Rarity.basic => const [1, 2, 3, 5, 7, 10],
    Rarity.adventurer => const [1, 1, 2, 3, 5, 7, 10],
    Rarity.hero => const [1, 1, 1, 1, 2, 2, 3, 3],
    Rarity.legend => const [1, 1, 1, 1, 1, 2, 2, 2, 3],
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
  int get upgradePoints =>
      copies -
      1 -
      [
        for (final (i, effect) in path.indexed)
          if (unlocked.contains(effect)) costs[i],
      ].fold(0, (a, b) => a + b);

  List<UpgradeEffect> get path => UpgradeTree.pathFor(card.rarity);

  /// What each step of [path] costs, in duplicates.
  List<int> get costs => UpgradeTree.costsFor(card.rarity);

  /// The first step of [path] not unlocked yet: upgrades unlocked before a
  /// path grew keep their place.
  UpgradeEffect? get nextUpgrade => path.where((e) => !unlocked.contains(e)).firstOrNull;

  /// The duplicates the next upgrade costs, or `null` once maxed out.
  int? get nextUpgradeCost => switch (nextUpgrade) {
    final next? => costs[path.indexOf(next)],
    null => null,
  };

  /// Whether the next upgrade can be unlocked, with enough duplicates or,
  /// [onCredit], without.
  bool canUpgrade({bool onCredit = false}) => nextUpgrade != null && (onCredit || upgradePoints >= nextUpgradeCost!);

  /// Whether there are enough duplicates for the next upgrade.
  bool get hasUnspentPoints => canUpgrade();

  bool has(UpgradeEffect effect) => unlocked.contains(effect);
}
