import 'dart:math';

import 'models.dart';
import 'themes.dart';
import 'upgrades.dart';

/// Every challenger goes through a 4 day loop, and every day each player
/// works on a different stage of it:
///   1. write a title prompt for a theme and a character,
///   2. draw a challenger from a prompt someone wrote the day before,
///   3. pick up to four fighters against a challenger drawn the day before,
///   4. vote on the fights the others set up the day before.
/// Afterwards the fights play out and everyone involved sees the outcome.
abstract final class LoopStep {
  static const prompt = 1;
  static const draw = 2;
  static const fight = 3;
  static const vote = 4;
}

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
    this.premade = false,
  });

  final String id;
  final Player author;
  final Player subject;
  final DailyTheme theme;
  final String title;
  final int day;

  /// [author] wrote nothing that day, so a premade title stands in.
  final bool premade;
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

  /// How strong a fighter of each rarity is, for [fighterOdds].
  static const rarityPower = {Rarity.basic: 1.0, Rarity.adventurer: 1.5, Rarity.hero: 2.2, Rarity.legend: 3.2};

  /// Extra power per unlocked upgrade.
  static const upgradePower = 0.3;

  /// How strong the challenger is against the whole team.
  static const challengerPower = 5.0;

  /// How likely the fighters win a vote decided by chance (and a simulated
  /// player thinks they win). The server decides missing votes the same way.
  double get fighterOdds {
    final team = fighters.fold(0.0, (sum, f) => sum + rarityPower[f.card.rarity]! + f.effects.length * upgradePower);
    return team / (team + challengerPower);
  }
}

/// One hit of an animated fight.
class FightBeat {
  const FightBeat({
    required this.attacker,
    required this.target,
    required this.damage,
    required this.challengerHp,
    required this.fighterHp,
  });

  /// The challenger.
  static const challenger = -1;

  /// All standing fighters attacking together.
  static const team = -2;

  /// [challenger], [team] or the index of a fighter.
  final int attacker;

  /// [challenger] or the index of a fighter.
  final int target;
  final int damage;
  final int challengerHp;
  final List<int> fighterHp;
}

/// Builds short fight animations.
abstract final class FightScript {
  static const maxHp = 100;

  /// A fight that ends with the outcome the votes decided. The fighters
  /// attack together, the challenger strikes one of them back.
  static List<FightBeat> build({required int fighterCount, required bool fightersWin, Random? random}) {
    final rng = random ?? Random();
    int roll(int min, int max) => min + rng.nextInt(max - min + 1);
    var challengerHp = maxHp;
    final fighterHp = List.filled(fighterCount, maxHp);
    final beats = <FightBeat>[];
    void add(int attacker, int target, int damage) => beats.add(
      FightBeat(
        attacker: attacker,
        target: target,
        damage: damage,
        challengerHp: challengerHp,
        fighterHp: List.unmodifiable(fighterHp),
      ),
    );

    while (true) {
      // The team strikes. Losing teams never land the final blow.
      var damage = fightersWin ? roll(30, 48) : roll(10, 22);
      if (!fightersWin) damage = min(damage, max(0, challengerHp - 10));
      damage = min(damage, challengerHp);
      challengerHp -= damage;
      add(FightBeat.team, FightBeat.challenger, damage);
      if (challengerHp == 0) break;

      // The challenger strikes back at one fighter.
      final alive = [
        for (var i = 0; i < fighterCount; i++)
          if (fighterHp[i] > 0) i,
      ];
      final target = alive[rng.nextInt(alive.length)];
      var hit = fightersWin ? roll(20, 45) : roll(70, 100);
      if (fightersWin && alive.length == 1) hit = min(hit, max(0, fighterHp[target] - 10));
      hit = min(hit, fighterHp[target]);
      fighterHp[target] -= hit;
      add(FightBeat.challenger, target, hit);
      if (fighterHp.every((hp) => hp == 0)) break;
    }
    return beats;
  }

  /// A few undecided exchanges for the voting screen. Nobody drops low
  /// enough to give the outcome away.
  static List<FightBeat> skirmish({required int fighterCount, Random? random}) {
    final rng = random ?? Random();
    var challengerHp = maxHp;
    final fighterHp = List.filled(fighterCount, maxHp);
    final beats = <FightBeat>[];
    for (var round = 0; round < 3; round++) {
      final damage = 8 + rng.nextInt(10);
      challengerHp -= damage;
      beats.add(
        FightBeat(
          attacker: FightBeat.team,
          target: FightBeat.challenger,
          damage: damage,
          challengerHp: challengerHp,
          fighterHp: List.unmodifiable(fighterHp),
        ),
      );
      final target = rng.nextInt(fighterCount);
      final hit = 8 + rng.nextInt(10);
      fighterHp[target] = max(45, fighterHp[target] - hit);
      beats.add(
        FightBeat(
          attacker: FightBeat.challenger,
          target: target,
          damage: hit,
          challengerHp: challengerHp,
          fighterHp: List.unmodifiable(fighterHp),
        ),
      );
    }
    return beats;
  }
}
