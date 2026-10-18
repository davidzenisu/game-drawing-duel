import 'dart:math';

import 'models.dart';
import 'themes.dart';
import 'upgrades.dart';

/// Every challenger goes through a 4 day loop, and every day each player
/// works on a different stage of it:
///   1. choose a player for a description and write their challenger title,
///   2. draw a challenger from a prompt someone wrote the day before,
///   3. pick up to four fighters against a challenger drawn the day before,
///   4. boost one of the challengers the others fought the day before.
/// The day after, the stars decide the fights and everyone involved sees
/// the outcome. Once a week comes step 5, the [Finale].
abstract final class LoopStep {
  static const prompt = 1;
  static const draw = 2;
  static const fight = 3;
  static const boost = 4;

  /// On the last day of every week, see [Finale].
  static const finale = 5;

  /// The first day with decided fights.
  static const results = 5;
}

/// Stars decide the fights: the fighters' rarities against the challenger's
/// stars, which grow with every boost.
abstract final class Stars {
  /// A challenger's stars before boosts.
  static const challengerBase = 3;

  /// The stars [boosts] add to a challenger: the first adds 1, the second 2,
  /// the third 3, and so on (1, 3, 6, … in total).
  static int ofBoosts(int boosts) => boosts * (boosts + 1) ~/ 2;

  /// A challenger's stars with [boosts].
  static int ofChallenger(int boosts) => challengerBase + ofBoosts(boosts);

  /// The stars of a team: its rarities'. Upgrades don't count (yet).
  static int ofTeam(Iterable<Rarity> team) => team.fold(0, (sum, rarity) => sum + rarity.stars);

  /// The fighters win with more stars than the boosted challenger; ties go
  /// to the challenger.
  static bool fightersWin(int fighterStars, int boosts) => fighterStars > ofChallenger(boosts);
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
      FighterEntry(card: owned.card, effects: List.unmodifiable(owned.unlocked), element: owned.element);

  final CharacterCard card;
  final List<UpgradeEffect> effects;
  final ElementKind? element;
}

/// Step 3 of the daily loop: up to four fighters against a new challenger.
/// The other players may boost the challenger the next day (step 4), and the
/// day after, the stars decide.
class FightSetup {
  FightSetup({
    required this.id,
    required this.owner,
    required this.challenger,
    required this.fighters,
    required this.day,
    this.boosts = 0,
  }) : assert(fighters.isNotEmpty && fighters.length <= maxFighters);

  static const maxFighters = 4;

  final String id;
  final Player owner;
  final CharacterCard challenger;
  final List<FighterEntry> fighters;

  /// The day the fighters were picked.
  final int day;

  /// How many players boosted the challenger. Online, it's only known once
  /// the fight is decided.
  int boosts;

  int get fighterStars => Stars.ofTeam(fighters.map((f) => f.card.rarity));

  int get challengerStars => Stars.ofChallenger(boosts);

  /// Ties go to the challenger.
  bool get fightersWin => Stars.fightersWin(fighterStars, boosts);
}

/// Step 4 of the daily loop: one of yesterday's challengers you may boost,
/// with the teams that were sent against it.
class BoostTarget {
  const BoostTarget({required this.challenger, required this.matchups});

  final CharacterCard challenger;
  final List<FightSetup> matchups;
}

/// A challenger you encountered (drew, fought against or boosted) and how
/// it fared in its decided fights. Challengers aren't part of the gacha pool.
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

  /// A few undecided exchanges for the boost screen. Nobody drops low
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

/// Step 5, on the last day of every week (Sunday, UTC): every challenger
/// that won a fight decided that week enters, and players vote on pairs of
/// them. Each vote adds a star; once the week is over, the one with the most
/// stars joins the gacha pool as a hero.
abstract final class Finale {
  /// Fights are decided this many days after their fighters were picked;
  /// they count for the week they're decided in.
  static const decidedAfter = 2;

  /// Whether [date] (UTC) is the last day of its week, the finale's.
  static bool isFinaleDate(DateTime date) => date.weekday == DateTime.sunday;
}

/// Where you stand in today's [Finale].
class FinaleBallot {
  const FinaleBallot({required this.pair, required this.votes, required this.pairs, required this.contenders});

  /// The next two challengers to pick one of, or null once you voted on
  /// every pair.
  final (CharacterCard, CharacterCard)? pair;

  /// How many pairs you voted on, of the [pairs] you may: every pair of the
  /// contenders without a challenger you drew.
  final int votes;
  final int pairs;

  /// The week's challengers that won a fight.
  final int contenders;
}

/// The winner of the latest [Finale], now in the gacha pool as a hero.
class WeeklyHero {
  const WeeklyHero({required this.card, required this.day, required this.stars, required this.votes});

  final CharacterCard card;

  /// The finale day it won on.
  final int day;

  /// Its stars in the end: its challenger stars with boosts, plus [votes].
  final int stars;
  final int votes;
}
