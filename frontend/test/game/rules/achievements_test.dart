import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/achievements.dart';
import 'package:frontend/game/rules/models.dart';

const _you = Player(id: 'p0', name: 'Pat', isYou: true);
const _players = [
  _you,
  Player(id: 'p1', name: 'Sam'),
  Player(id: 'p2', name: 'Kim'),
  Player(id: 'p3', name: 'Jo'),
  Player(id: 'p4', name: 'Ali'),
];

CharacterCard _card(
  String id, {
  required String artist,
  required String subject,
  Rarity rarity = Rarity.basic,
  int day = 0,
}) => CharacterCard(
  id: id,
  subject: subject,
  title: id,
  rarity: rarity,
  prompt: 'basic',
  artist: artist,
  sketch: const Sketch([]),
  day: day,
);

void main() {
  final pool = [
    _card('a', artist: 'Sam', subject: 'Kim'),
    _card('b', artist: 'Sam', subject: 'Pat', rarity: Rarity.legend),
    _card('c', artist: 'Pat', subject: 'Sam', rarity: Rarity.adventurer),
    _card('d', artist: 'Kim', subject: 'Pat'),
    // A weekly hero: not a starter.
    _card('w', artist: 'Jo', subject: 'Sam', rarity: Rarity.hero, day: 7),
  ];

  List<Achievement> of({
    Set<String> owned = const {'c'},
    List<int> margins = const [],
    Set<String> collected = const {},
    bool speed = false,
  }) => AchievementRewards.of(
    players: _players,
    pool: pool,
    owned: owned,
    fightMargins: margins,
    collected: collected,
    speed: speed,
  );

  test('the players with starter heroes, rarities, wins, streaks and close calls', () {
    expect(of().map((a) => a.key), [
      'artist:1', 'artist:2', // not you, nor Jo and Ali who drew no starter
      'portrait:0', 'portrait:1', 'portrait:2',
      'rarity:basic', 'rarity:adventurer', 'rarity:legend',
      for (final n in [1, 3, 5, 10, 25, 50]) 'wins:$n',
      for (var n = 1; n <= 25; n++) 'streak:$n',
      for (final n in [1, 3, 5, 10, 25, 50]) 'close:$n',
    ]);
    expect(of().where((a) => a.kind.leveled).map((a) => a.stars).toSet(), {5});
    final sams = of().first;
    expect((sams.title, sams.goal, sams.progress, sams.stars), ("Sam's gallery", 2, 0, 10), reason: '5 players');
    expect(of().firstWhere((a) => a.key == 'portrait:0').title, 'Your portraits');
    expect(of().firstWhere((a) => a.key == 'rarity:legend').stars, 20);
  });

  test('owning every starter hero of a set reaches it', () {
    final done = of(owned: {'a', 'b', 'c'}).firstWhere((a) => a.key == 'artist:1');
    expect((done.done, done.collectable), (true, true));
    final collected = of(owned: {'a', 'b'}, collected: {'artist:1'}).first;
    expect((collected.collected, collected.collectable), (true, false));
  });

  test('wins count, and a loss starts a streak over', () {
    final achievements = {
      for (final a in of(margins: [2, 1, -1, 3, 1, 4])) a.key: a,
    };
    expect(achievements['wins:3']!.done, isTrue);
    expect(achievements['wins:10']!.progress, 5);
    expect(achievements['streak:3']!.done, isTrue);
    expect(achievements['streak:5']!.progress, 3);
    expect(achievements['close:1']!.done, isTrue);
    expect(achievements['close:3']!.progress, 2);
  });

  test('a tie is lost, and only a win by one star is a close call', () {
    final achievements = {
      for (final a in of(margins: [0, 2])) a.key: a,
    };
    expect(achievements['wins:1']!.progress, 1);
    expect(achievements['close:1']!.progress, 0);
  });

  test('speed mode lists no fight levels out of reach', () {
    expect(of(speed: true).where((a) => a.kind.leveled).map((a) => a.key), [
      'wins:1',
      'wins:3',
      'streak:1',
      'streak:2',
      'streak:3',
      'close:1',
      'close:3',
    ]);
  });

  test('only the next level of each kind shows', () {
    List<String> shown(List<int> margins, Set<String> collected) => [
      for (final a in AchievementRewards.nextLevels(of(margins: margins, collected: collected)))
        if (a.kind.leveled) a.key,
    ];
    expect(shown([], {}), ['wins:1', 'streak:1', 'close:1']);
    expect(shown([2, 2, 2], {'wins:1', 'streak:1', 'streak:3'}), [
      'wins:3',
      'streak:2',
      'close:1',
    ], reason: 'the lowest not collected, reached or not');
    final everyStreak = {for (var n = 1; n <= 25; n++) 'streak:$n'};
    expect(shown([], everyStreak), ['wins:1', 'streak:25', 'close:1'], reason: 'the top one once all are collected');
    List<String> keys(Iterable<Achievement> list) => [
      for (final a in list)
        if (!a.kind.leveled) a.key,
    ];
    expect(keys(AchievementRewards.nextLevels(of())), keys(of()), reason: 'the others all show');
  });

  test('fewer players earn more for a player set', () {
    expect([for (var n = 5; n <= 10; n++) AchievementRewards.forPlayers(n)], [10, 9, 8, 7, 6, 5]);
    expect(AchievementRewards.forPlayers(3), 10);
  });
}
