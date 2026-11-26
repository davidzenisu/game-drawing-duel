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
/// the heroes' share of the week before's decided fights from Monday to
/// Saturday, once there were at least [minFights]: winning more than a share
/// of [more] gives that many more stars (the most of every share beaten),
/// less than a share of [fewer] that many fewer (the most of every share
/// undercut). Never fewer than [minStars] or more than [maxStars]. A week's
/// stars are the ones its challengers are boosted with: boosted the day
/// before they're fought, from the Sunday before to its Saturday. Speed mode
/// sessions have no weeks, so they keep [Boost.stars].
abstract final class WeeklyBoost {
  static const minFights = 6;
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

/// A week's boost stars a day, the ones its challengers are boosted with,
/// and why: the week before's ([previousStars]) changed by [step], the
/// heroes having won [heroWins] of its decided [fights], from [fromDay] to
/// [toDay] (Monday to Saturday).
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
/// the players whose portraits theirs beat most of the time in last week's
/// Arena. A vote for a challenger portraying one player over one portraying
/// another is a matchup the first player won; draws and matchups of two
/// portraits of the same player don't count, and each voter's first
/// [matchupsPerVoter] votes on a pair of players count. The server counts
/// them. Speed mode sessions have none.
abstract final class WinRates {
  /// The matchups it takes for a win rate to count.
  static const minMatchups = 10;

  /// How many of each voter's votes on a pair of players count.
  static const matchupsPerVoter = 10;

  /// Winning at least a share (in whole percent) of the matchups gives
  /// these extra stars: the most of every share reached.
  static const extraStarsByShare = [(0.6, 1)];

  /// The extra stars for winning [wins] of [matchups] last week, by
  /// [bands]. Shares count in whole percent, so 6 of 10 reaches 60%.
  static int extraStars(int wins, int matchups, [List<(double, int)> bands = extraStarsByShare]) {
    if (matchups < minMatchups) return 0;
    return bands.fold(0, (most, tier) => wins * 100 >= (tier.$1 * 100).round() * matchups ? max(most, tier.$2) : most);
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
  static const quickMessages = ['No pressure 😇', 'You can do it 💪', 'Hurry crew 👩‍🚀'];

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

/// Once a week, the finale: the week's challengers are ranked one place at
/// a time ([order]) by their boost stars, then whether their artist has no
/// drawing ranked above them yet, then the boost stars all of their
/// artist's challengers got that week, then their win rate, then the latest
/// day they were drawn. A challenger counts for the week of its fight, two days after
/// it was drawn (titled on Monday, it's fought on Thursday; titled on
/// Friday, it's fought on Monday and counts for the next week). Once the
/// week is over (Sunday, UTC), its top [maxHeroes] are crowned weekly heroes
/// and join the gacha pool, with the [rarities] of their places.
abstract final class Finale {
  /// Whether [date] (UTC) is the last day of its week, the finale's.
  static bool isFinaleDate(DateTime date) => date.weekday == DateTime.sunday;

  /// The rarities of the weekly heroes: 1st place a legend, 2nd a hero, 3rd
  /// an adventurer.
  static const rarities = [Rarity.legend, Rarity.hero, Rarity.adventurer];
  static const maxHeroes = 3;

  /// The indexes of a week's challengers, each (artist, boost stars, its
  /// artist's boost stars, fights won, fights, day), best first, picked one
  /// place at a time: the most boost stars, then one whose artist has no
  /// drawing ranked above it yet, then the most boost stars of its artist,
  /// then the best win rate (none without fights), then the latest day, then
  /// the first in [entries].
  static List<int> order(List<(Object, int, int, int, int, int)> entries) {
    final ranked = <Object>{};
    // Negative when [a] ranks above [b] for the next place.
    int compare(int i, int j) {
      final a = entries[i], b = entries[j];
      if (a.$2 != b.$2) return b.$2.compareTo(a.$2);
      final (aRanked, bRanked) = (ranked.contains(a.$1), ranked.contains(b.$1));
      if (aRanked != bRanked) return aRanked ? 1 : -1;
      if (a.$3 != b.$3) return b.$3.compareTo(a.$3);
      // The win rates, none without fights.
      final (aWins, aFights) = a.$5 == 0 ? (0, 1) : (a.$4, a.$5);
      final (bWins, bFights) = b.$5 == 0 ? (0, 1) : (b.$4, b.$5);
      if (aWins * bFights != bWins * aFights) return (bWins * aFights).compareTo(aWins * bFights);
      if (a.$6 != b.$6) return b.$6.compareTo(a.$6);
      return i.compareTo(j);
    }

    final left = [for (var i = 0; i < entries.length; i++) i];
    final order = <int>[];
    while (left.isNotEmpty) {
      final best = left.reduce((i, j) => compare(i, j) <= 0 ? i : j);
      left.remove(best);
      order.add(best);
      ranked.add(entries[best].$1);
    }
    return order;
  }
}

/// A hero of the latest [Finale], now in the gacha pool with the rarity it
/// was crowned with (its [card]'s).
class WeeklyHero {
  const WeeklyHero({required this.card, required this.day, required this.stars, this.place = 1});

  final CharacterCard card;

  /// The finale day it was crowned on: the last day of its week.
  final int day;

  /// Its own stars plus its boost stars.
  final int stars;

  /// Its place in the week's ranking, 1 to [Finale.maxHeroes].
  final int place;
}

/// A challenger in a week's ranking.
class RankedChallenger {
  const RankedChallenger({
    required this.card,
    required this.stars,
    required this.fights,
    required this.wins,
    this.place = 1,
    this.heroRarity,
    this.artistBoostStars = 0,
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

  /// Its place in the ranking ([Finale.order]); a weekly hero's is the
  /// one it was crowned with.
  final int place;

  /// The boost stars all of its artist's challengers ranked that week got,
  /// its own included: the ranking's first tiebreak.
  final int artistBoostStars;

  /// The rarity it was crowned with as a weekly hero; null if it wasn't
  /// (always in speed mode).
  final Rarity? heroRarity;

  bool get isWeeklyHero => heroRarity != null;

  /// Its fights won out of its fights, in percent; null without any.
  int? get winPercent => fights == 0 ? null : (100 * wins / fights).round();

  /// What [Finale.order] ranks it by.
  (Object, int, int, int, int, int) get rankedBy => (card.artist, boostStars, artistBoostStars, wins, fights, card.day);

  /// This one at [place], crowned with [heroRarity] if given, with
  /// [artistBoostStars] if given.
  RankedChallenger at(int place, {Rarity? heroRarity, int? artistBoostStars}) => RankedChallenger(
    card: card,
    stars: stars,
    fights: fights,
    wins: wins,
    place: place,
    heroRarity: heroRarity ?? this.heroRarity,
    artistBoostStars: artistBoostStars ?? this.artistBoostStars,
    promptAuthor: promptAuthor,
    defaultPrompt: defaultPrompt,
    boosts: boosts,
    foughtBy: foughtBy,
  );

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
  const WeekRanking({required this.day, required this.challengers});

  /// The last day of the week.
  final int day;
  final List<RankedChallenger> challengers;

  /// Its weekly heroes, by place.
  List<RankedChallenger> get heroes => [
    for (final c in challengers)
      if (c.isWeeklyHero) c,
  ]..sort((a, b) => a.place.compareTo(b.place));
}

/// The Arena: everyone votes on matchups of two of the week before's
/// challengers that its finale didn't crown, never their own drawings, and
/// once that week of votes is over its top [maxWinners] become Arena
/// winners, for the Arena banner, with the finale's [rarities] by place.
///
/// Week X's challengers are fought in week X; the Arena of week X opens once
/// its finale is decided (on Monday of week X+1) and is decided once week
/// X+1 is over, so the first one opens in a server's second week, and the
/// Arena banner in its third. The server rates and ranks the votes
/// (`backend/app/arena.py`); both sides check these numbers against
/// `shared/rules.json`.
abstract final class Arena {
  static const rarities = Finale.rarities;
  static const maxWinners = Finale.maxHeroes;

  /// A day's first matchups earn [packStars] stars once all are voted on;
  /// voting goes on after them, unrewarded, up to the day's cap ([cap]).
  static const pack = 10;
  static const packStars = 3;

  /// A challenger takes part in this many matchups at least to be ranked,
  /// and crowned; the others are left unranked. An Arena where none does
  /// crowns nobody.
  static const minMatchups = 5;

  /// How many matchups you can vote on today, with [pairsLeft] pairs you
  /// haven't voted on at the start of the day and [daysLeft] days of the
  /// Arena, today included: as many as you like, as long as a [pack]'s
  /// pairs stay for every day after today, so the daily stars never run out
  /// before the Arena ends; but always the pack while pairs are left.
  static int cap(int pairsLeft, int daysLeft) {
    if (pairsLeft <= 0 || daysLeft <= 0) return 0;
    final spare = pairsLeft - pack * (daysLeft - 1);
    return min(pairsLeft, max(pack, spare));
  }
}

/// The Arena open today, as you see it ([Arena]).
class ArenaStatus {
  const ArenaStatus({
    required this.week,
    required this.endsOn,
    required this.challengers,
    required this.votesToday,
    required this.cap,
    required this.pack,
    this.packStars = Arena.packStars,
    this.rewarded = false,
  });

  /// The last day of its challengers' week, and the last day to vote.
  final int week;
  final int endsOn;

  /// How many challengers it holds.
  final int challengers;

  /// Your votes today, and the most you can cast today.
  final int votesToday;
  final int cap;

  /// The votes today's [packStars] take: the pack, or the cap if lower.
  final int pack;
  final int packStars;

  /// Whether today's pack earned its stars already.
  final bool rewarded;

  /// The votes left until today's stars; 0 once they're earned.
  int get packLeft => rewarded ? 0 : max(0, pack - votesToday);

  /// Whether you can vote again today.
  bool get canVote => votesToday < cap;
}

/// Your Arena today: its status and the next matchup to vote on, null at
/// today's cap or without pairs left, and the one after it, to show below
/// it (null if the next is today's last vote).
class ArenaRound {
  const ArenaRound({required this.status, this.matchup, this.next});

  /// Null when no Arena is open (the first week, speed mode).
  final ArenaStatus? status;
  final (CharacterCard, CharacterCard)? matchup;
  final (CharacterCard, CharacterCard)? next;
}

/// Whether [a] and [b] are the same pair of challengers, in either order.
bool samePair((CharacterCard, CharacterCard)? a, (CharacterCard, CharacterCard)? b) =>
    a != null && b != null && {a.$1.id, a.$2.id}.containsAll([b.$1.id, b.$2.id]);

/// A winner of the latest Arena, now in the gacha pool with the rarity it
/// was crowned with.
class ArenaWinner {
  const ArenaWinner({required this.card, required this.week, required this.place});

  final CharacterCard card;

  /// The last day of its challengers' week.
  final int week;

  /// Its place in the Arena, 1 to [Arena.maxWinners].
  final int place;
}

/// A challenger in a decided Arena.
class ArenaRanked {
  const ArenaRanked({
    required this.card,
    required this.place,
    required this.score,
    required this.matchups,
    this.rating = 1,
    this.winnerRarity,
    this.qualified = true,
  });

  final CharacterCard card;

  /// Its place: the winners' first, by place, then the others'.
  final int place;

  /// Its score in its matchups (a draw counts a half), and how many.
  final double score;
  final int matchups;

  /// Its strength from all of the Arena's votes.
  final double rating;

  /// The rarity it was crowned with as an Arena winner; null if it wasn't.
  final Rarity? winnerRarity;

  bool get isWinner => winnerRarity != null;

  /// Whether it took part in enough matchups to be ranked, and crowned
  /// ([Arena.minMatchups]); the others come last, unranked.
  final bool qualified;

  /// Its score as text: "6½ of 8".
  String get record {
    final whole = score.floor();
    final half = score - whole >= 0.5;
    return '${whole == 0 && half ? '' : whole}${half ? '½' : ''} of $matchups';
  }
}

/// The latest decided Arena, best first.
class ArenaRanking {
  const ArenaRanking({
    required this.week,
    required this.endsOn,
    required this.challengers,
    this.minMatchups = Arena.minMatchups,
  });

  /// The last day of its challengers' week, and of its week of votes.
  final int week;
  final int endsOn;
  final List<ArenaRanked> challengers;

  /// The matchups a challenger needed to be ranked, and crowned.
  final int minMatchups;

  /// Its winners, by place.
  List<ArenaRanked> get winners => [
    for (final c in challengers)
      if (c.isWinner) c,
  ];
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
    secretThisWeek: true,
  ),
  busyStreak(
    'busy-streak',
    'Addict',
    'Days in a row, across weeks, they did every step they could: title, drawing, boost and fight',
    'days',
  ),
  mostHurried('most-hurried', 'Hurry Crew', 'Hurries they received, on the day each hit', 'hurries'),
  mostPrompted(
    'most-prompted',
    'Prompt Engineer',
    'Boost stars the challengers drawn from titles they wrote got (not premade ones), in the week of their fight',
    '★',
    secretThisWeek: true,
  );

  const PlayerStatKind(this.key, this.label, this.description, this.unit, {this.secretThisWeek = false});

  /// Its name in the API.
  final String key;
  final String label;
  final String description;
  final String unit;

  /// Hidden until the week is over: it would tell how strong a drawing is.
  final bool secretThisWeek;

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

  /// Hidden until the week is over: [PlayerStatKind.mostBoosted] and
  /// [PlayerStatKind.mostPrompted] would tell how strong a drawing is.
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
    this.boostBalance,
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

  /// This week only: its boost stars, the ones its challengers are boosted
  /// with, and why; null in the first week.
  final BoostBalance? boostBalance;
}

/// How [player]'s portraits did against [against]'s in last week's Arena,
/// and the extra stars that gives their characters against that player this
/// week.
class WinRate {
  const WinRate({
    required this.player,
    required this.against,
    required this.matchups,
    required this.wins,
    this.bands = WinRates.extraStarsByShare,
  });

  final Player player;
  final Player against;

  /// The Arena matchups of their portraits that counted, and how many
  /// [player] won.
  final int matchups;
  final int wins;

  /// The win rate bands of the week they count for (see [WeekWinRates.bands]).
  final List<(double, int)> bands;

  int get extraStars => WinRates.extraStars(wins, matchups, bands);
}

/// This week's win rates, from the Arena voted on during the days [fromDay]
/// to [toDay] (on the challengers of the week before them): every pair of
/// players whose portraits met, both ways.
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

  /// The extra stars for winning more than a share of the matchups, as the
  /// server counts them this week.
  final List<(double, int)> bands;

  /// The extra stars [player]'s characters get against [against]'s.
  int extraStars(String player, String against) =>
      rates.where((r) => r.player.name == player && r.against.name == against).firstOrNull?.extraStars ?? 0;
}
