import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';

/// Checks the rules against `shared/rules.json`, which the backend's tests
/// check its own implementation against too.
void main() {
  final rules = jsonDecode(File('../shared/rules.json').readAsStringSync()) as Map<String, dynamic>;
  List<Player> roster(int count) => [for (var i = 0; i < count; i++) Player(id: 'p$i', name: 'Player $i')];

  /// Every artist's subjects as roster indexes.
  List<List<int>> subjects(List<Player> players, List<DrawingAssignment> Function(List<Player>, int) assign) => [
    for (var i = 0; i < players.length; i++) [for (final a in assign(players, i)) players.indexOf(a.subject)],
  ];

  test('limits', () {
    expect(SetupPlan.minPlayers, rules['players']['min']);
    expect(SetupPlan.maxPlayers, rules['players']['max']);
    expect(CharacterCard.maxTitleLength, rules['max_title_length']);
  });

  test('rarities', () {
    expect([
      for (final r in Rarity.values) {'name': r.name, 'stars': r.stars, 'draw_seconds': r.drawTime?.inSeconds},
    ], rules['rarities']);
  });

  test('setup prompts', () {
    expect([
      for (final p in SetupPrompt.values) {'name': p.name, 'rarity': p.rarity.name, 'based_on': p.basedOn?.name},
    ], rules['setup_prompts']);
  });

  test('setup plans', () {
    expect({
      for (var n = SetupPlan.minPlayers; n <= SetupPlan.maxPlayers; n++)
        '$n': [for (final p in SetupPlan.promptsFor(n)) p.name],
    }, rules['setup_plans']);
    expect([for (final p in SetupPlan.testPrompts) p.name], rules['test_setup']);
  });

  test('assignments', () {
    for (final MapEntry(:key, :value) in (rules['assignments'] as Map<String, dynamic>).entries) {
      expect(subjects(roster(int.parse(key)), SetupPlan.assignmentsFor), value, reason: '$key players');
    }
    for (final MapEntry(:key, :value) in (rules['test_assignments'] as Map<String, dynamic>).entries) {
      expect(subjects(roster(int.parse(key)), SetupPlan.testAssignmentsFor), value, reason: '$key active players');
    }
  });
}
