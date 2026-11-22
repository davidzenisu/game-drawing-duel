import 'models.dart';

/// What an [Achievement] asks for.
enum AchievementKind {
  /// Own every starter hero (setup drawing) another player drew.
  artist,

  /// Own every starter hero portraying a player, you included.
  portrait,

  /// Own every starter hero of a rarity.
  rarity,

  /// Win this many fights you picked the fighters for.
  wins,

  /// Win this many of those fights in a row.
  streak,

  /// Win this many of those fights by exactly one star: a close call.
  close;

  /// Has levels, of which the rewards screen shows the next one only
  /// ([AchievementRewards.nextLevels]).
  bool get leveled => this == wins || this == streak || this == close;
}

/// A goal you reach on your own, rewarded once with [stars] you collect
/// ([GameSession.collectAchievement]).
class Achievement {
  const Achievement({
    required this.key,
    required this.kind,
    required this.goal,
    required this.progress,
    required this.stars,
    this.player,
    this.rarity,
    this.collected = false,
  });

  /// Names it, e.g. "artist:2" or "wins:3".
  final String key;
  final AchievementKind kind;

  /// The player of an artist or portrait achievement.
  final Player? player;

  /// The rarity of a rarity achievement.
  final Rarity? rarity;
  final int goal;

  /// Towards [goal], at most the goal.
  final int progress;
  final int stars;
  final bool collected;

  bool get done => progress >= goal;

  /// Done, with its stars not collected yet.
  bool get collectable => done && !collected;

  String get title => switch (kind) {
    AchievementKind.artist => "${player!.name}'s gallery",
    AchievementKind.portrait => player!.isYou ? 'Your portraits' : 'Portraits of ${player!.name}',
    AchievementKind.rarity => 'Every starter ${rarity!.label}',
    AchievementKind.wins => goal == 1 ? 'First win' : '$goal wins',
    AchievementKind.streak => '$goal wins in a row',
    AchievementKind.close => goal == 1 ? 'Close Call' : '$goal Close Calls',
  };

  String get description => switch (kind) {
    AchievementKind.artist => 'Summon every starter hero ${player!.name} drew.',
    AchievementKind.portrait => 'Summon every starter hero portraying ${player!.isYou ? 'you' : player!.name}.',
    AchievementKind.rarity => 'Summon every ${rarity!.stars} star starter hero.',
    AchievementKind.wins => 'Win ${goal == 1 ? 'a fight' : '$goal fights'} you picked the fighters for.',
    AchievementKind.streak => 'Win $goal of your fights in a row. A lost one starts over.',
    AchievementKind.close =>
      'Win ${goal == 1 ? 'a fight' : '$goal fights'} you picked the fighters for by exactly one star, like 9 against 8.',
  };
}

/// The rewards of the achievements, in stars. Checked against
/// `shared/rules.json`.
abstract final class AchievementRewards {
  /// For a player's starter heroes (as artist or portrayed), by the number
  /// of players in the roster: fewer is harder.
  static const playerStars = {5: 10, 6: 9, 7: 8, 8: 7, 9: 6, 10: 5};

  /// For every starter hero of a rarity.
  static const rarityStars = {Rarity.basic: 10, Rarity.adventurer: 15, Rarity.legend: 20};

  /// Fights won, won in a row and won by exactly one star, and the reward
  /// of each level.
  static const wins = [1, 3, 5, 10, 25, 50];
  static final streaks = [for (var n = 3; n <= 25; n++) n];
  static const closeCalls = [1, 3, 5, 10, 25, 50];
  static const fightStars = 5;

  /// A speed mode session has no fight levels above this one: it has no
  /// more fights of your own.
  static const speedMaxGoal = 3;

  static int forPlayers(int players) {
    final counts = playerStars.keys;
    return playerStars[players.clamp(counts.reduce((a, b) => a < b ? a : b), counts.reduce((a, b) => a > b ? a : b))]!;
  }

  /// Your achievements, like the backend works them out: the players' first
  /// (the other artists, then the portraits), then the rarities, the wins,
  /// the streaks and the close calls, each level from the lowest. [pool]'s
  /// day 0 cards are the starter heroes; [fightMargins] are the fights you
  /// picked, in order, each by the fighters' stars minus the challenger's
  /// (extra stars included): won above 0, a close call at 1. A [speed] mode
  /// session has no levels above [speedMaxGoal].
  static List<Achievement> of({
    required List<Player> players,
    required List<CharacterCard> pool,
    required Set<String> owned,
    required List<int> fightMargins,
    required Set<String> collected,
    bool speed = false,
  }) {
    final starters = pool.where((c) => c.day == 0).toList();
    final reward = forPlayers(players.length);
    final entries = <Achievement>[];
    void add(String key, AchievementKind kind, int goal, int progress, int stars, {Player? player, Rarity? rarity}) {
      entries.add(
        Achievement(
          key: key,
          kind: kind,
          goal: goal,
          progress: progress > goal ? goal : progress,
          stars: stars,
          player: player,
          rarity: rarity,
          collected: collected.contains(key),
        ),
      );
    }

    void addSet(
      String key,
      AchievementKind kind,
      Iterable<CharacterCard> heroes,
      int stars, {
      Player? player,
      Rarity? rarity,
    }) {
      if (heroes.isEmpty) return;
      add(
        key,
        kind,
        heroes.length,
        heroes.where((c) => owned.contains(c.id)).length,
        stars,
        player: player,
        rarity: rarity,
      );
    }

    for (final (position, player) in players.indexed) {
      if (player.isYou) continue;
      addSet(
        'artist:$position',
        AchievementKind.artist,
        starters.where((c) => c.artist == player.name),
        reward,
        player: player,
      );
    }
    for (final (position, player) in players.indexed) {
      addSet(
        'portrait:$position',
        AchievementKind.portrait,
        starters.where((c) => c.subject == player.name),
        reward,
        player: player,
      );
    }
    for (final MapEntry(key: rarity, value: stars) in rarityStars.entries) {
      addSet(
        'rarity:${rarity.name}',
        AchievementKind.rarity,
        starters.where((c) => c.rarity == rarity),
        stars,
        rarity: rarity,
      );
    }
    var won = 0, streak = 0, best = 0, close = 0;
    for (final margin in fightMargins) {
      final win = margin > 0;
      streak = win ? streak + 1 : 0;
      if (win) won++;
      if (margin == 1) close++;
      if (streak > best) best = streak;
    }
    for (final (kind, goals, progress) in [
      (AchievementKind.wins, wins, won),
      (AchievementKind.streak, streaks, best),
      (AchievementKind.close, closeCalls, close),
    ]) {
      for (final n in goals) {
        if (!speed || n <= speedMaxGoal) add('${kind.name}:$n', kind, n, progress, fightStars);
      }
    }
    return entries;
  }

  /// [achievements] as the rewards screen shows them: of a leveled kind
  /// only the next level, the lowest not collected yet (or the top one once
  /// every level is collected), in place of the others.
  static List<Achievement> nextLevels(Iterable<Achievement> achievements) {
    final next = <AchievementKind, Achievement>{};
    for (final a in achievements.where((a) => a.kind.leveled)) {
      final shown = next[a.kind];
      if (shown == null ||
          (shown.collected && !a.collected) ||
          (shown.collected == a.collected && (a.collected ? a.goal > shown.goal : a.goal < shown.goal))) {
        next[a.kind] = a;
      }
    }
    return [
      for (final a in achievements)
        if (!a.kind.leveled || identical(next[a.kind], a)) a,
    ];
  }
}
