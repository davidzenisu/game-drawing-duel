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

FightSetup _fight(int fighters, {int boostStars = 0}) => FightSetup(
  id: 'f',
  owner: _player,
  challenger: _card,
  fighters: List.filled(fighters, const FighterEntry(card: _card)),
  day: 4,
  boostStars: boostStars,
);

void main() {
  test('stars decide the winner, ties go to the challenger', () {
    // Heroes have 3 stars, like a challenger before boosts.
    expect((_fight(1).fighterStars, _fight(1).challengerStars), (3, 3));
    expect(_fight(1).fightersWin, isFalse);
    expect(_fight(2).fightersWin, isTrue);
    // Boost stars add to the challenger's.
    final boosted = _fight(2, boostStars: 3);
    expect((boosted.fighterStars, boosted.challengerStars), (6, 6));
    expect(boosted.fightersWin, isFalse);
    expect(_fight(3, boostStars: 3).fightersWin, isTrue);
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
}
