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
/// Once a week, the [Finale] ranks the week's challengers.
abstract final class LoopStep {
  static const prompt = 1;
  static const draw = 2;
  static const boost = 3;
  static const fight = 4;
}

/// Speed mode: a one-off session of about 20 minutes. Its setup and days
/// run on timers, back to back; a day ends early once everyone is done.
/// Challenger prompts are written on the first days only, so the last days
/// finish the loop; after the last day the session is over.
abstract final class SpeedMode {
  static const setup = Duration(seconds: 300);
  static const days = [
    Duration(seconds: 60),
    Duration(seconds: 120),
    Duration(seconds: 180),
    Duration(seconds: 180),
    Duration(seconds: 120),
    Duration(seconds: 60),
  ];
  static const lastPromptDay = 3;

  /// The whole session, if no day ends early.
  static Duration get total => days.fold(setup, (a, b) => a + b);
}

/// Step 3: every day, you spread the week's boost stars across up to
/// [challengers] of the challengers drawn the day before, all of them on one
/// at most. Once the day is over, chance spreads the ones you left.
abstract final class Boost {
  static const challengers = 3;

  /// The stars to give a day in the first week and in speed mode; after
  /// that, [WeeklyBoost] balances them.
  static const stars = 3;
}

/// Each week starts from the week before's boost stars and changes them by
/// the heroes' share of the week before's decided fights, once there were
/// at least [minFights]: winning more than a share of [more] gives that many
/// more stars (the most of every share beaten), less than a share of
/// [fewer] that many fewer (the most of every share undercut). Never fewer
/// than [minStars] or more than [maxStars]. Speed mode sessions have no
/// weeks, so they keep [Boost.stars].
abstract final class WeeklyBoost {
  static const minFights = 7;
  static const more = [(0.6, 1), (0.8, 2)];
  static const fewer = [(0.4, 1), (0.2, 2)];
  static const minStars = 3;
  static const maxStars = 6;

  /// How many boost stars more (or fewer) a week gives after the heroes won
  /// [heroWins] of the week before's [fights].
  static int step(int heroWins, int fights) {
    if (fights < minFights) return 0;
    final up = more.fold(0, (most, tier) => heroWins > tier.$1 * fights ? max(most, tier.$2) : most);
    final down = fewer.fold(0, (most, tier) => heroWins < tier.$1 * fights ? max(most, tier.$2) : most);
    return up - down;
  }

  /// A week's boost stars: the week before's changed by [step], within
  /// [minStars] and [maxStars].
  static int stars(int previous, int step) => (previous + step).clamp(minStars, maxStars);
}

/// A week's boost stars a day, and why: the week before's ([previousStars])
/// changed by [step], the heroes having won [heroWins] of its decided
/// [fights], from [fromDay] to [toDay].
class BoostBalance {
  const BoostBalance({
    required this.fromDay,
    required this.toDay,
    required this.fights,
    required this.heroWins,
    required this.previousStars,
    required this.step,
    required this.stars,
    this.minFights = WeeklyBoost.minFights,
  });

  final int fromDay;
  final int toDay;
  final int fights;
  final int heroWins;
  final int previousStars;
  final int step;
  final int stars;

  /// The fights it takes to change the stars.
  final int minFights;

  int get challengerWins => fights - heroWins;

  /// The heroes' share of the fights, in percent, rounded.
  int get heroPercent => fights == 0 ? 0 : (100 * heroWins / fights).round();

  /// Whether there were enough fights to count.
  bool get counted => fights >= minFights;

  /// How the stars changed from the week before's, within the limits.
  int get change => stars - previousStars;
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

  /// The fighters win with more stars than the boosted challenger, each side
  /// with its [WinRates] extra stars; ties go to the challenger.
  static bool fightersWin(
    int fighterStars,
    int boostStars, {
    int fighterExtraStars = 0,
    int challengerExtraStars = 0,
  }) => fighterStars + fighterExtraStars > ofChallenger(boostStars) + challengerExtraStars;
}

/// After each week, a player's characters get extra stars this week against
/// the players whose characters they beat most of the time last week.
/// Characters count for the player they depict, and every fighter meets the
/// challenger once. Speed mode sessions have none.
abstract final class WinRates {
  /// The meetings it takes for a win rate to count.
  static const minFights = 3;

  /// Winning more than a share of the meetings gives these extra stars: the
  /// most of every share beaten.
  static const extraStarsByShare = [(0.6, 1), (0.8, 2)];

  /// The extra stars for winning [wins] of [fights] last week, by [bands].
  static int extraStars(int wins, int fights, [List<(double, int)> bands = extraStarsByShare]) {
    if (fights < minFights) return 0;
    return bands.fold(0, (most, tier) => wins > tier.$1 * fights ? max(most, tier.$2) : most);
  }
}

/// The time limit for drawing a challenger.
const challengerDrawTime = Duration(seconds: 90);

/// Free daily hurries: what one takes away when it hits, and when the
/// hurries a player receives hit. Every one counts.
/// Stars, the currency players collect: writing a challenger title and
/// drawing a challenger earn these, and a won fight the challenger's stars
/// ([FightSetup.challengerStars]). Checked against `shared/rules.json`.
abstract final class StarRewards {
  static const prompt = 3;
  static const challenger = 3;

  /// Stars buy a pull for this many: a pull tops up the pulls you're short
  /// of with them.
  static const pullPrice = 10;

  /// Once a week is over, the first place of each player stat wins a
  /// trophy worth these stars, as a gift; tied first places each win one.
  static const weekStat = 3;
}

abstract final class Hurries {
  /// The drawing time a hurry takes away when it hits.
  static const cut = Duration(seconds: 5);

  /// Hurries hit with between these times left, spread out.
  static const firstLeft = Duration(seconds: 55);
  static const lastLeft = Duration(seconds: 15);

  /// The longest short message a hurry's sender can add.
  static const messageMaxLength = 60;

  /// Quick picks for the message, in the send dialog.
  static const quickMessages = ['Tick tock ⏰', 'Hurry up!', 'No pressure 😇', 'Draw faster! 🐢'];

  /// The time left at which each of a day's hurries hits, in the order they
  /// were sent, from a random share in [0, 1) each (its jitter).
  ///
  /// They're spread evenly: the window's time not taken by the cuts of the
  /// hurries before is split into one stretch per hurry, and each hits
  /// somewhere in its own, so together they never run past [lastLeft].
  static List<Duration> hits(List<double> jitters) {
    final first = _seconds(firstLeft), last = _seconds(lastLeft), cut = _seconds(Hurries.cut);
    final n = jitters.length;
    final room = max(0.0, first - last - (n - 1) * cut);
    return [for (final (i, jitter) in jitters.indexed) _duration(first - i * cut - room / n * (i + jitter))];
  }

  static double _seconds(Duration d) => d.inMicroseconds / Duration.microsecondsPerSecond;

  static Duration _duration(double seconds) =>
      Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
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
  const FighterEntry({required this.card, this.effects = const [], this.element, this.extraStars = 0});

  factory FighterEntry.fromOwned(OwnedCard owned, {int extraStars = 0}) => FighterEntry(
    card: owned.card,
    effects: List.unmodifiable(owned.shown),
    element: owned.element,
    extraStars: extraStars,
  );

  final CharacterCard card;
  final List<UpgradeEffect> effects;
  final ElementKind? element;

  /// Its [WinRates] extra stars against the challenger's player.
  final int extraStars;
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
    this.challengerExtraStars = 0,
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

  /// The challenger's [WinRates] extra stars against the fighters' players.
  final int challengerExtraStars;

  /// The fighters' rarities' stars, without their extra stars.
  int get fighterStars => Stars.ofTeam(fighters.map((f) => f.card.rarity));

  /// The fighters' [WinRates] extra stars, all together.
  int get fighterExtraStars => fighters.fold(0, (sum, f) => sum + f.extraStars);

  /// The challenger's own and boost stars, without its extra stars: what a
  /// win pays in stars.
  int get challengerStars => Stars.ofChallenger(boostStars);

  /// Both sides' stars in the fight, extra stars included.
  int get fighterTotal => fighterStars + fighterExtraStars;
  int get challengerTotal => challengerStars + challengerExtraStars;

  /// Ties go to the challenger.
  bool get fightersWin => Stars.fightersWin(
    fighterStars,
    boostStars,
    fighterExtraStars: fighterExtraStars,
    challengerExtraStars: challengerExtraStars,
  );
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
/// A past day with fights to replay.
class FightDay {
  const FightDay({required this.day, required this.date});

  final int day;

  /// The calendar day it was played on.
  final DateTime date;
}

class ChallengerRecord {
  const ChallengerRecord({
    required this.card,
    required this.fights,
    required this.wins,
    this.starsToCollect = 0,
    this.starsCollected = 0,
  });

  final CharacterCard card;

  /// Decided fights against it.
  final int fights;

  /// Decided fights it won.
  final int wins;

  /// For its artist: the challenger's stars in every decided fight it won,
  /// to collect ([GameSession.collectChallengerStars]), and the ones
  /// collected already.
  final int starsToCollect;
  final int starsCollected;

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
/// of its fight, two days after it was drawn (titled on Monday, it's fought
/// on Thursday; titled on Friday, it's fought on Monday and counts for the
/// next week). Once the week is over (Sunday, UTC), the one with the most
/// stars joins the gacha pool as a hero.
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
  const RankedChallenger({
    required this.card,
    required this.stars,
    required this.fights,
    required this.wins,
    this.promptAuthor,
    this.defaultPrompt = false,
    this.boosts = const [],
    this.foughtBy = const [],
  });

  final CharacterCard card;

  /// Its own stars plus its boost stars.
  final int stars;

  /// Its fights by the end of the week, and how many of them it won.
  final int fights;
  final int wins;

  /// Who wrote its prompt: the player before its artist. [defaultPrompt]
  /// when they wrote none, so it was drawn from a premade title.
  final Player? promptAuthor;
  final bool defaultPrompt;

  /// Its boost stars, by player.
  final List<ChallengerBoost> boosts;

  /// Its fights by the end of the week.
  final List<ChallengerFight> foughtBy;

  int get boostStars => stars - Stars.challengerBase;
}

/// Boost stars a player gave a challenger: their own, or spread by chance
/// from the ones they didn't give ([byChance], shown as "default").
class ChallengerBoost {
  const ChallengerBoost({required this.booster, required this.stars, this.byChance = false});

  final Player booster;
  final int stars;
  final bool byChance;
}

/// A fight of a challenger: who picked fighters against it, and whether it
/// won.
class ChallengerFight {
  const ChallengerFight({required this.player, required this.challengerWon});

  final Player player;
  final bool challengerWon;
}

/// The latest finished week's challengers, most stars first; the first
/// joined the gacha pool as a hero.
class WeekRanking {
  const WeekRanking({required this.day, required this.challengers, this.boostBalance});

  /// The last day of the week.
  final int day;
  final List<RankedChallenger> challengers;

  /// The boost stars its fights gave the week after; null in speed mode.
  final BoostBalance? boostBalance;
}

/// The week the player stats count (see [PlayerStats]).
enum StatPeriod {
  week('week', 'This week'),
  lastWeek('last-week', 'Last week');

  const StatPeriod(this.key, this.label);

  /// Its name in the API.
  final String key;
  final String label;
}

/// A category of the player stats: every player ranked by it, its first
/// places winning a trophy once the week is over ([StarRewards.weekStat]).
enum PlayerStatKind {
  mostWins('most-wins', 'Giant Slayer', 'Fights won, of the ones they picked the fighters for', 'wins'),
  mostBoosted(
    'most-boosted',
    'Grand Artist',
    'Boost stars the challengers they drew got, in the week of their fight',
    '★',
  ),
  busyStreak(
    'busy-streak',
    'Addict',
    'Days in a row, across weeks, they did every step they could: title, drawing, boost and fight',
    'days',
  );

  const PlayerStatKind(this.key, this.label, this.description, this.unit);

  /// Its name in the API.
  final String key;
  final String label;
  final String description;
  final String unit;

  static PlayerStatKind? byKey(String key) => values.where((k) => k.key == key).firstOrNull;
}

/// A player's value of a stat and their place (tied players share one),
/// both null while the stat is secret; and the [trophies] they won in it.
class PlacedPlayer {
  const PlacedPlayer({required this.player, required this.value, required this.place, this.trophies = 0});

  final Player player;
  final int? value;
  final int? place;
  final int trophies;

  /// A first place, worth a trophy once the week is over.
  bool get first => place == 1 && (value ?? 0) > 0;
}

/// A player stat, with every player best first; in roster order while it's
/// [secret].
class PlayerStat {
  const PlayerStat({required this.kind, required this.players, this.secret = false});

  final PlayerStatKind kind;
  final List<PlacedPlayer> players;

  /// Hidden until the week is over: [PlayerStatKind.mostBoosted] would tell
  /// how strong a drawing is.
  final bool secret;

  /// [values] (and the trophies won) ranked best first, then in the order
  /// given; tied players share a place, the next one skips theirs.
  static PlayerStat rank(PlayerStatKind kind, List<(Player, int, int)> values) {
    final sorted = [...values.indexed]
      ..sort((a, b) {
        final byValue = b.$2.$2.compareTo(a.$2.$2);
        return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
      });
    final placed = <PlacedPlayer>[];
    for (final (i, (_, (player, value, trophies))) in sorted.indexed) {
      final place = placed.isNotEmpty && placed.last.value == value ? placed.last.place : i + 1;
      placed.add(PlacedPlayer(player: player, value: value, place: place, trophies: trophies));
    }
    return PlayerStat(kind: kind, players: placed);
  }
}

/// How the players did from [fromDay] to [toDay], a category at a time.
/// Once a week is over, each category's first places win a trophy worth
/// [trophyStars], as a gift.
class PlayerStats {
  const PlayerStats({
    required this.period,
    required this.fromDay,
    required this.toDay,
    required this.trophyStars,
    required this.stats,
    this.portrayed = const [],
  });

  final StatPeriod period;
  final int fromDay;
  final int toDay;
  final int trophyStars;
  final List<PlayerStat> stats;

  /// Every player of the roster, with how many of the challengers the week
  /// ranks (fought that week) portray them, drawn so far; without their
  /// stars.
  final List<(Player, int)> portrayed;
}

/// How [player]'s characters did against [against]'s last week, and the
/// extra stars that gives them against that player this week.
class WinRate {
  const WinRate({
    required this.player,
    required this.against,
    required this.fights,
    required this.wins,
    this.bands = WinRates.extraStarsByShare,
  });

  final Player player;
  final Player against;

  /// The meetings of their characters, and how many [player] won.
  final int fights;
  final int wins;

  /// The win rate bands of the week they count for (see [WeekWinRates.bands]).
  final List<(double, int)> bands;

  int get extraStars => WinRates.extraStars(wins, fights, bands);
}

/// This week's win rates, from the fights of the days [fromDay] to [toDay]:
/// every pair of players whose characters met, both ways.
class WeekWinRates {
  const WeekWinRates({
    required this.fromDay,
    required this.toDay,
    required this.rates,
    this.bands = WinRates.extraStarsByShare,
  });

  final int fromDay;
  final int toDay;
  final List<WinRate> rates;

  /// The extra stars for winning more than a share of the meetings, as the
  /// server counts them this week: the weeks before the boost balance's
  /// first one kept older bands.
  final List<(double, int)> bands;

  /// The extra stars [player]'s characters get against [against]'s.
  int extraStars(String player, String against) =>
      rates.where((r) => r.player.name == player && r.against.name == against).firstOrNull?.extraStars ?? 0;

  /// Every meeting of a fighter and the challenger in [fights], and who won
  /// it. Fighters of the challenger's own player don't count.
  static List<WinRate> count(Iterable<FightSetup> fights, Player Function(String name) player) {
    final meetings = <(String, String), int>{};
    final won = <(String, String), int>{};
    for (final fight in fights) {
      final challenger = fight.challenger.subject;
      for (final fighter in fight.fighters) {
        final subject = fighter.card.subject;
        if (subject == challenger) continue;
        final (winner, loser) = fight.fightersWin ? (subject, challenger) : (challenger, subject);
        for (final pair in [(winner, loser), (loser, winner)]) {
          meetings[pair] = (meetings[pair] ?? 0) + 1;
        }
        won[(winner, loser)] = (won[(winner, loser)] ?? 0) + 1;
      }
    }
    return [
      for (final MapEntry(key: (a, b), value: n) in meetings.entries)
        WinRate(player: player(a), against: player(b), fights: n, wins: won[(a, b)] ?? 0),
    ];
  }
}
