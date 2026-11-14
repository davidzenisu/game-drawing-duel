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
    List<bool> won = const [],
    Set<String> collected = const {},
  }) => AchievementRewards.of(players: _players, pool: pool, owned: owned, fightsWon: won, collected: collected);

  test('the players with starter heroes, rarities, wins and streaks', () {
    expect(of().map((a) => a.key), [
      'artist:1', 'artist:2', // not you, nor Jo and Ali who drew no starter
      'portrait:0', 'portrait:1', 'portrait:2',
      'rarity:basic', 'rarity:adventurer', 'rarity:legend',
      'wins:1', 'wins:3', 'wins:10', 'streak:3', 'streak:5',
    ]);
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
      for (final a in of(won: [true, true, false, true, true, true])) a.key: a,
    };
    expect(achievements['wins:3']!.done, isTrue);
    expect(achievements['wins:10']!.progress, 5);
    expect(achievements['streak:3']!.done, isTrue);
    expect(achievements['streak:5']!.progress, 3);
  });

  test('fewer players earn more for a player set', () {
    expect([for (var n = 5; n <= 10; n++) AchievementRewards.forPlayers(n)], [10, 9, 8, 7, 6, 5]);
    expect(AchievementRewards.forPlayers(3), 10);
  });
}
