import 'dart:math';

import 'models.dart';

/// The default prompts of the initial drawing setup.
enum SetupPrompt {
  basic(rarity: Rarity.basic, label: 'Basic', hint: 'Just them, as you know them.'),
  alter(
    rarity: Rarity.basic,
    label: 'Alter',
    hint: 'An alternative version of your basic drawing.',
    basedOn: SetupPrompt.basic,
  ),
  knight(rarity: Rarity.adventurer, label: 'Knight', hint: 'Draw them as a knight.'),
  mage(rarity: Rarity.adventurer, label: 'Mage', hint: 'Draw them as a mage.'),
  rogue(rarity: Rarity.adventurer, label: 'Rogue', hint: 'Draw them as a rogue.'),
  legend(rarity: Rarity.legend, label: 'A legend', hint: 'Draw them as a true legend. Take your time.');

  const SetupPrompt({required this.rarity, required this.label, required this.hint, this.basedOn});

  final Rarity rarity;
  final String label;
  final String hint;

  /// The prompt this one builds on; it is drawn of the same subject.
  final SetupPrompt? basedOn;
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
///
/// The server enforces the same rules (`backend/app/rules.py`); both are
/// checked against `shared/rules.json`.
abstract final class SetupPlan {
  static const minPlayers = 5;
  static const maxPlayers = 10;

  /// The short setup of a test session, drawn by every player who joined:
  /// one character per rarity tier that exists at setup.
  static const testPrompts = [SetupPrompt.basic, SetupPrompt.knight, SetupPrompt.legend];

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

  /// The assignments of the player at [artistIndex] in a regular server.
  static List<DrawingAssignment> assignmentsFor(List<Player> players, int artistIndex) =>
      _assign(players, artistIndex, promptsFor(players.length));

  /// The assignments of the player at [artistIndex] in a test session:
  /// [testPrompts] of different, randomly picked other [players] of the whole
  /// roster, whether they joined or not.
  static List<DrawingAssignment> testAssignmentsFor(List<Player> players, int artistIndex, Random random) {
    final others = [...players]
      ..removeAt(artistIndex)
      ..shuffle(random);
    return [
      for (final (i, prompt) in testPrompts.indexed)
        DrawingAssignment(id: '${players[artistIndex].id}-${prompt.name}', prompt: prompt, subject: others[i]),
    ];
  }

  /// Every prompt group (the alter shares its subject with the basic) shifts
  /// the subject by a different offset, so nobody draws themselves and every
  /// player is depicted exactly once per prompt.
  static List<DrawingAssignment> _assign(List<Player> players, int artistIndex, List<SetupPrompt> prompts) {
    final count = players.length;
    final assignments = <DrawingAssignment>[];
    var group = -1;
    for (final prompt in prompts) {
      if (prompt.basedOn == null) group++;
      final offset = 1 + group % (count - 1);
      final subject = players[(artistIndex + offset) % count];
      final basedOn = prompt.basedOn;
      assignments.add(
        DrawingAssignment(
          id: '${players[artistIndex].id}-${prompt.name}',
          prompt: prompt,
          subject: subject,
          basedOn: basedOn == null ? null : assignments.firstWhere((a) => a.prompt == basedOn).id,
        ),
      );
    }
    return assignments;
  }
}
