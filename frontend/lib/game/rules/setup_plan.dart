import 'models.dart';

/// The default prompts of the initial drawing setup.
enum SetupPrompt {
  basic(rarity: Rarity.basic, label: 'Basic', hint: 'Just them, as you know them.'),
  alter(rarity: Rarity.basic, label: 'Alter', hint: 'An alternative version of your basic drawing.'),
  knight(rarity: Rarity.adventurer, label: 'Knight', hint: 'Draw them as a knight.'),
  mage(rarity: Rarity.adventurer, label: 'Mage', hint: 'Draw them as a mage.'),
  rogue(rarity: Rarity.adventurer, label: 'Rogue', hint: 'Draw them as a rogue.'),
  legend(rarity: Rarity.legend, label: 'A legend', hint: 'Draw them as a true legend. Take your time.');

  const SetupPrompt({required this.rarity, required this.label, required this.hint});

  final Rarity rarity;
  final String label;
  final String hint;
}

/// A drawing a player has to make during the initial setup.
class DrawingAssignment {
  const DrawingAssignment({required this.id, required this.prompt, required this.subject, this.basedOn});

  final String id;
  final SetupPrompt prompt;
  final Player subject;

  /// The assignment this one builds on (the alter is based on the basic).
  final String? basedOn;
}

/// Works out who draws what so that the pool always holds roughly 30
/// characters at launch, see `docs/concept/initial-setup.md`.
abstract final class SetupPlan {
  static const minPlayers = 5;
  static const maxPlayers = 10;

  static bool supports(int playerCount) => playerCount >= minPlayers && playerCount <= maxPlayers;

  /// The prompts every player draws for a server of [playerCount] players.
  static List<SetupPrompt> promptsFor(int playerCount) {
    if (!supports(playerCount)) {
      throw ArgumentError.value(playerCount, 'playerCount', 'must be between $minPlayers and $maxPlayers');
    }
    return switch (playerCount) {
      5 => SetupPrompt.values,
      6 => const [SetupPrompt.basic, SetupPrompt.alter, SetupPrompt.knight, SetupPrompt.mage, SetupPrompt.legend],
      7 || 8 => const [SetupPrompt.basic, SetupPrompt.knight, SetupPrompt.mage, SetupPrompt.legend],
      _ => const [SetupPrompt.basic, SetupPrompt.knight, SetupPrompt.legend],
    };
  }

  static int drawingsPerPlayer(int playerCount) => promptsFor(playerCount).length;

  /// Total number of characters in the pool at launch, per rarity.
  static Map<Rarity, int> poolAtLaunch(int playerCount) {
    final counts = {for (final rarity in Rarity.values) rarity: 0};
    for (final prompt in promptsFor(playerCount)) {
      counts[prompt.rarity] = counts[prompt.rarity]! + playerCount;
    }
    return counts;
  }

  /// The assignments of the player at [artistIndex].
  ///
  /// Every prompt group (the alter shares its subject with the basic) shifts
  /// the subject by a different offset, so nobody draws themselves and every
  /// player is depicted exactly once per prompt.
  static List<DrawingAssignment> assignmentsFor(List<Player> players, int artistIndex) {
    final count = players.length;
    final assignments = <DrawingAssignment>[];
    var group = -1;
    for (final prompt in promptsFor(count)) {
      if (prompt != SetupPrompt.alter) group++;
      final offset = 1 + group % (count - 1);
      final subject = players[(artistIndex + offset) % count];
      final basedOn = prompt == SetupPrompt.alter
          ? assignments.firstWhere((a) => a.prompt == SetupPrompt.basic).id
          : null;
      assignments.add(
        DrawingAssignment(
          id: '${players[artistIndex].id}-${prompt.name}',
          prompt: prompt,
          subject: subject,
          basedOn: basedOn,
        ),
      );
    }
    return assignments;
  }
}
