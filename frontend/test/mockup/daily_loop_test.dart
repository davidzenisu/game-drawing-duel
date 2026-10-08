import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/mockup/logic/daily_loop.dart';
import 'package:frontend/mockup/logic/models.dart';

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
  test('votes decide the winner, ties go to the challenger', () {
    final fight = _fight(2);
    fight.votes.addAll({'a': true, 'b': false});
    expect(fight.fightersWin, isFalse);
    fight.votes['c'] = true;
    expect(fight.fightersWin, isTrue);
    expect(fight.fighterVotes, 2);
    expect(fight.challengerVotes, 1);
  });

  test('more and rarer fighters have better odds', () {
    expect(_fight(4).fighterOdds, greaterThan(_fight(1).fighterOdds));
  });

  test('fight scripts always end with the voted outcome', () {
    for (var fighters = 1; fighters <= FightSetup.maxFighters; fighters++) {
      for (final fightersWin in [true, false]) {
        for (var seed = 0; seed < 100; seed++) {
          final beats = FightScript.build(fighterCount: fighters, fightersWin: fightersWin, random: Random(seed));
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
