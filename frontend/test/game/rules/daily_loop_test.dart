import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/models.dart';

const _card = CharacterCard(
  id: 'c',
  subject: 'Sam',
  title: 'Night Shift',
  rarity: Rarity.hero,
  prompt: 'Challenger',
  artist: 'Kim',
  sketch: Sketch.empty,
);

const _player = Player(id: 'p1', name: 'Kim');

FightSetup _fight(int fighters) => FightSetup(
  id: 'f',
  owner: _player,
  challenger: _card,
  fighters: List.filled(fighters, const FighterEntry(card: _card)),
  day: 3,
);

void main() {
  test('stars decide the winner, ties go to the challenger', () {
    // Heroes have 3 stars, like a challenger before boosts.
    expect((_fight(1).fighterStars, _fight(1).challengerStars), (3, 3));
    expect(_fight(1).fightersWin, isFalse);
    expect(_fight(2).fightersWin, isTrue);
    // Two boosts add 1 + 2 stars.
    final boosted = _fight(2)..boosts = 2;
    expect((boosted.fighterStars, boosted.challengerStars), (6, 6));
    expect(boosted.fightersWin, isFalse);
    expect((_fight(4)..boosts = 2).fightersWin, isTrue);
  });

  test('every boost adds a star more than the one before', () {
    expect([for (var n = 0; n <= 4; n++) Stars.ofBoosts(n)], [0, 1, 3, 6, 10]);
  });

  test('fight scripts always end with the decided outcome', () {
    for (var fighters = 1; fighters <= FightSetup.maxFighters; fighters++) {
      for (final fightersWin in [true, false]) {
        for (var seed = 0; seed < 100; seed++) {
          final beats = FightScript.build(fighterCount: fighters, fightersWin: fightersWin, random: Random(seed));
          expect(beats.length, lessThanOrEqualTo(16), reason: 'fights stay short');
          final last = beats.last;
          final reason = '$fighters fighters, fightersWin $fightersWin, seed $seed';
          if (fightersWin) {
            expect(last.challengerHp, 0, reason: reason);
            expect(last.fighterHp.any((hp) => hp > 0), isTrue, reason: reason);
          } else {
            expect(last.challengerHp, greaterThan(0), reason: reason);
            expect(last.fighterHp.every((hp) => hp == 0), isTrue, reason: reason);
          }
        }
      }
    }
  });

  test('skirmishes on the voting screen never give the outcome away', () {
    for (var seed = 0; seed < 50; seed++) {
      final beats = FightScript.skirmish(fighterCount: 4, random: Random(seed));
      expect(beats, isNotEmpty);
      for (final beat in beats) {
        expect(beat.challengerHp, greaterThan(40));
        expect(beat.fighterHp.every((hp) => hp >= 45), isTrue);
      }
    }
  });
}
