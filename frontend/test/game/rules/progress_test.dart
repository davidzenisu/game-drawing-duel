import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/progress.dart';
import 'package:frontend/game/rules/upgrades.dart';

CharacterCard _card(String id, Rarity rarity) => CharacterCard(
  id: id,
  subject: 'S',
  title: 'T',
  rarity: rarity,
  prompt: rarity.label,
  artist: 'A',
  sketch: Sketch.empty,
);

void main() {
  test('progress counts collected, maxed out, upgrades and duplicates by rarity', () {
    final basics = [for (var i = 0; i < 3; i++) _card('b$i', Rarity.basic)];
    final legend = _card('l', Rarity.legend);
    final pool = [...basics, legend];
    // One maxed basic with 4 spare duplicates, one with 2 upgrades and 1
    // spare, the third basic and the legend not summoned.
    final maxed = OwnedCard(basics[0])..copies = 1 + 28 + 4;
    maxed.unlocked.addAll(maxed.path);
    final halfway = OwnedCard(basics[1])
      ..copies = 1 + 3 + 1
      ..unlocked.addAll([UpgradeEffect.shadow, UpgradeEffect.outline]);
    // A challenger pulled before it left the pool.
    final outside = OwnedCard(_card('c', Rarity.hero))..copies = 2;

    final progress = Progress.byRarity(pool, [maxed, halfway, outside]);
    final basic = progress[Rarity.basic]!;
    expect((basic.inPool, basic.collected, basic.owned, basic.maxed), (3, 2, 2, 1));
    expect((basic.unlockedSteps, basic.steps), (6 + 2, 12));
    // The halfway one needs 3 + 5 + 7 + 10 more, minus its spare one.
    expect(basic.duplicatesToMax, 25 - 1);
    expect(basic.spareDuplicates, 4 + 1, reason: 'the maxed out one counts too');

    final legends = progress[Rarity.legend]!;
    expect((legends.inPool, legends.collected, legends.owned), (1, 0, 0));
    final heroes = progress[Rarity.hero]!;
    expect((heroes.inPool, heroes.collected, heroes.owned), (0, 0, 1), reason: 'owned, but not in the pool');
    expect(heroes.duplicatesToMax, UpgradeTree.costsFor(Rarity.hero).fold(0, (a, b) => a + b) - 1);

    final total = progress.values.fold(Progress.empty, (a, b) => a + b);
    expect((total.inPool, total.collected, total.owned, total.maxed), (4, 2, 3, 1));
  });
}
