import 'dart:math';

import 'models.dart';
import 'themes.dart';
import 'upgrades.dart';

/// Step 1 of the daily loop: a title prompt for a challenger, written for a
/// theme and a character. Another player draws it the next day.
class ChallengerPrompt {
  const ChallengerPrompt({
    required this.id,
    required this.author,
    required this.subject,
    required this.theme,
    required this.title,
    required this.day,
  });

  final String id;
  final Player author;
  final Player subject;
  final DailyTheme theme;
  final String title;
  final int day;
}

/// A character sent into a fight, with the effects it had at that time.
class FighterEntry {
  const FighterEntry({required this.card, this.effects = const [], this.element});

  factory FighterEntry.fromOwned(OwnedCard owned) =>
      FighterEntry(card: owned.card, effects: List.unmodifiable(owned.unlocked), element: owned.element);

  final CharacterCard card;
  final List<UpgradeEffect> effects;
  final ElementKind? element;
}

/// Step 3 of the daily loop: up to four fighters against a new challenger.
/// The other players vote on the winner the next day (step 4).
class FightSetup {
  FightSetup({
    required this.id,
    required this.owner,
    required this.challenger,
    required this.fighters,
    required this.day,
  }) : assert(fighters.isNotEmpty && fighters.length <= maxFighters);

  static const maxFighters = 4;

  final String id;
  final Player owner;
  final CharacterCard challenger;
  final List<FighterEntry> fighters;

  /// The day the fighters were picked.
  final int day;

  /// Voter id to whether they think the fighters win.
  final Map<String, bool> votes = {};

  int get fighterVotes => votes.values.where((v) => v).length;

  int get challengerVotes => votes.length - fighterVotes;

  /// Ties go to the challenger.
  bool get fightersWin => fighterVotes > challengerVotes;

  /// How likely a simulated player thinks the fighters win.
  double get fighterOdds {
    double power(Rarity rarity) => switch (rarity) {
      Rarity.basic => 1.0,
      Rarity.adventurer => 1.5,
      Rarity.hero => 2.2,
      Rarity.legend => 3.2,
    };
    final team = fighters.fold(0.0, (sum, f) => sum + power(f.card.rarity) + f.effects.length * 0.3);
    return team / (team + 5);
  }
}

/// One hit of a replayed fight. Index -1 is the challenger.
class FightBeat {
  const FightBeat({
    required this.attacker,
    required this.target,
    required this.damage,
    required this.challengerHp,
    required this.fighterHp,
  });

  final int attacker;
  final int target;
  final int damage;
  final int challengerHp;
  final List<int> fighterHp;
}

/// Builds a fight animation that ends with the outcome the votes decided.
abstract final class FightScript {
  static const maxHp = 100;

  static List<FightBeat> build({required int fighterCount, required bool fightersWin, Random? random}) {
    final rng = random ?? Random();
    var challengerHp = maxHp;
    final fighterHp = List.filled(fighterCount, maxHp);
    final beats = <FightBeat>[];
    int roll(int min, int max) => min + rng.nextInt(max - min + 1);
    void add(int attacker, int target, int damage) => beats.add(
      FightBeat(
        attacker: attacker,
        target: target,
        damage: damage,
        challengerHp: challengerHp,
        fighterHp: List.unmodifiable(fighterHp),
      ),
    );

    // The winners hit hard, the losers never land the final blow.
    final perFighterHit = (maxHp / (fighterCount * 3)).round();
    while (challengerHp > 0 && fighterHp.any((hp) => hp > 0)) {
      for (var i = 0; i < fighterCount && challengerHp > 0; i++) {
        if (fighterHp[i] == 0) continue;
        var damage = fightersWin
            ? roll((perFighterHit * 0.7).round(), (perFighterHit * 1.3).round())
            : roll(3, max(4, 30 ~/ fighterCount));
        if (!fightersWin) damage = min(damage, max(0, challengerHp - 8));
        damage = min(max(damage, fightersWin ? 1 : 0), challengerHp);
        challengerHp -= damage;
        add(i, -1, damage);
      }
      if (challengerHp == 0) break;
      final alive = [
        for (var i = 0; i < fighterCount; i++)
          if (fighterHp[i] > 0) i,
      ];
      final target = alive[rng.nextInt(alive.length)];
      var damage = fightersWin ? roll(15, 40) : roll(35, 60);
      if (fightersWin && alive.length == 1) damage = min(damage, max(0, fighterHp[target] - 5));
      damage = min(damage, fighterHp[target]);
      fighterHp[target] -= damage;
      add(-1, target, damage);
    }
    return beats;
  }
}
