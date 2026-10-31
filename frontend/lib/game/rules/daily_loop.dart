import 'dart:math';

import 'models.dart';
import 'themes.dart';
import 'upgrades.dart';

/// Every challenger goes through a 4 day loop, and every day each player
/// works on a different stage of it:
///   1. choose a player for a description and write their challenger title,
///   2. draw a challenger from a prompt someone wrote the day before,
///   3. spread boost stars across a few of the challengers drawn the day
///      before,
///   4. pick up to four fighters against a challenger drawn two days
///      before; the stars decide right away.
/// The day after, everyone involved sees the outcome. Once a week, the
/// [Finale] ranks the week's challengers.
abstract final class LoopStep {
  static const prompt = 1;
  static const draw = 2;
  static const boost = 3;
  static const fight = 4;

  /// The first day with yesterday's fights to show.
  static const results = 5;
}

/// Step 3: every day, you spread [stars] across up to [challengers] of the
/// challengers drawn the day before, at most [maxPerChallenger] on one. Once
/// the day is over, chance spreads the ones you left.
abstract final class Boost {
  static const challengers = 3;
  static const stars = 3;
  static const maxPerChallenger = 3;
}

/// Stars decide the fights: the fighters' rarities against the challenger's
/// stars and its boost stars.
abstract final class Stars {
  /// A challenger's stars before boosts.
  static const challengerBase = 3;

  /// A challenger's stars with [boostStars].
  static int ofChallenger(int boostStars) => challengerBase + boostStars;

  /// The stars of a team: its rarities'. Upgrades don't count (yet).
  static int ofTeam(Iterable<Rarity> team) => team.fold(0, (sum, rarity) => sum + rarity.stars);

  /// The fighters win with more stars than the boosted challenger; ties go
  /// to the challenger.
  static bool fightersWin(int fighterStars, int boostStars) => fighterStars > ofChallenger(boostStars);
}

/// The time limit for drawing a challenger.
const challengerDrawTime = Duration(seconds: 90);

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
    this.hint,
    this.premade = false,
  });

  final String id;
  final Player author;
  final Player subject;
  final DailyTheme theme;
  final String title;
  final int day;

  /// The description [author] chose [subject] and wrote [title] for, e.g. "a
  /// sauna regular"; null for a premade title.
  final String? hint;

  /// The question [author] answered, e.g. "Who is a sauna regular?".
  String? get question => hint == null ? null : 'Who is $hint?';

  /// [author] wrote nothing that day, so a premade title stands in.
  final bool premade;
}

/// A character sent into a fight, with the effects it had at that time.
class FighterEntry {
  const FighterEntry({required this.card, this.effects = const [], this.element});

  factory FighterEntry.fromOwned(OwnedCard owned) =>
      FighterEntry(card: owned.card, effects: List.unmodifiable(owned.shown), element: owned.element);

  final CharacterCard card;
  final List<UpgradeEffect> effects;
  final ElementKind? element;
}

/// Step 4 of the daily loop: up to four fighters against a challenger the
/// others boosted the day before. The stars decide right away.
class FightSetup {
  FightSetup({
    required this.id,
    required this.owner,
    required this.challenger,
    required this.fighters,
    required this.day,
    required this.boostStars,
  }) : assert(fighters.isNotEmpty && fighters.length <= maxFighters);

  static const maxFighters = 4;

  final String id;
  final Player owner;
  final CharacterCard challenger;
  final List<FighterEntry> fighters;

  /// The day the fighters were picked.
  final int day;

  /// The boost stars the challenger got the day before.
  final int boostStars;

  int get fighterStars => Stars.ofTeam(fighters.map((f) => f.card.rarity));

  int get challengerStars => Stars.ofChallenger(boostStars);

  /// Ties go to the challenger.
  bool get fightersWin => Stars.fightersWin(fighterStars, boostStars);
}

/// Step 3 of the daily loop: one of yesterday's challengers you may boost,
/// and the boost stars you gave it today.
class BoostTarget {
  const BoostTarget({required this.challenger, this.stars = 0});

  final CharacterCard challenger;
  final int stars;
}

/// A challenger you encountered (drew, fought against or boosted) and how
/// it fared in its fights of the days before. Challengers aren't part of the
/// gacha pool.
class ChallengerRecord {
  const ChallengerRecord({required this.card, required this.fights, required this.wins});

  final CharacterCard card;

  /// Decided fights against it.
  final int fights;

  /// Decided fights it won.
  final int wins;

  /// The share of its decided fights it won, or null before any was decided.
  double? get winRate => fights == 0 ? null : wins / fights;
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

  /// A fight that ends with the outcome the stars decided. The fighters
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
}

/// Once a week, the finale: the week's challengers are ranked by their
/// stars, their own and their boost stars. A challenger counts for the week
/// of its boosting day, so its stars are final once the week is over (Sunday,
/// UTC); then the one with the most stars joins the gacha pool as a hero.
abstract final class Finale {
  /// Whether [date] (UTC) is the last day of its week, the finale's.
  static bool isFinaleDate(DateTime date) => date.weekday == DateTime.sunday;
}

/// The winner of the latest [Finale], now in the gacha pool as a hero.
class WeeklyHero {
  const WeeklyHero({required this.card, required this.day, required this.stars});

  final CharacterCard card;

  /// The finale day it won on: the last day of its week.
  final int day;

  /// Its own stars plus its boost stars.
  final int stars;
}

/// A challenger in a week's ranking.
class RankedChallenger {
  const RankedChallenger({required this.card, required this.stars, required this.fights, required this.wins});

  final CharacterCard card;

  /// Its own stars plus its boost stars.
  final int stars;

  /// Its fights by the end of the week, and how many of them it won.
  final int fights;
  final int wins;
}

/// The latest finished week's challengers, most stars first; the first
/// joined the gacha pool as a hero.
class WeekRanking {
  const WeekRanking({required this.day, required this.challengers});

  /// The last day of the week.
  final int day;
  final List<RankedChallenger> challengers;
}
