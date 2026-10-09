import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';

List<Player> players(int count) => [for (var i = 0; i < count; i++) Player(id: 'p$i', name: 'Player $i')];

void main() {
  test('drawings per player follow the concept table', () {
    expect({for (var n = 5; n <= 10; n++) n: SetupPlan.drawingsPerPlayer(n)}, {5: 6, 6: 5, 7: 4, 8: 4, 9: 3, 10: 3});
  });

  test('the pool holds roughly 30 characters at launch', () {
    for (var n = SetupPlan.minPlayers; n <= SetupPlan.maxPlayers; n++) {
      final pool = SetupPlan.poolAtLaunch(n);
      final total = pool.values.reduce((a, b) => a + b);
      expect(total, inInclusiveRange(27, 32), reason: '$n players');
      expect(pool[Rarity.legend], n, reason: 'everyone draws one legend');
      expect(pool[Rarity.hero], 0, reason: 'heroes come from daily challengers');
    }
  });

  test('unsupported player counts are rejected', () {
    expect(() => SetupPlan.promptsFor(4), throwsArgumentError);
    expect(() => SetupPlan.promptsFor(11), throwsArgumentError);
  });

  test('nobody draws themselves and everyone is drawn once per prompt', () {
    for (var n = SetupPlan.minPlayers; n <= SetupPlan.maxPlayers; n++) {
      final roster = players(n);
      final all = [for (var i = 0; i < n; i++) ...SetupPlan.assignmentsFor(roster, i).map((a) => (artist: i, a: a))];
      for (final (:artist, :a) in all) {
        expect(a.subject.id, isNot(roster[artist].id));
      }
      for (final prompt in SetupPlan.promptsFor(n)) {
        final subjects = all.where((e) => e.a.prompt == prompt).map((e) => e.a.subject.id).toList();
        expect(subjects.toSet(), hasLength(n), reason: '$n players, ${prompt.name}');
      }
    }
  });

  test('the alter is based on the basic and shares its subject', () {
    final assignments = SetupPlan.assignmentsFor(players(5), 2);
    final basic = assignments.firstWhere((a) => a.prompt == SetupPrompt.basic);
    final alter = assignments.firstWhere((a) => a.prompt == SetupPrompt.alter);
    expect(alter.basedOn, basic.id);
    expect(alter.subject.id, basic.subject.id);
  });
}
