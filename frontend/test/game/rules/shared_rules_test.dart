import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';
import 'package:frontend/game/rules/themes.dart';
import 'package:frontend/game/rules/upgrades.dart';

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
  });

  test('test sessions draw different, random other players', () {
    final random = Random(1);
    for (var n = SetupPlan.minPlayers; n <= SetupPlan.maxPlayers; n++) {
      final players = roster(n);
      final seen = <String>{};
      for (var artist = 0; artist < n; artist++) {
        for (var i = 0; i < 20; i++) {
          final planned = SetupPlan.testAssignmentsFor(players, artist, random);
          expect([for (final a in planned) a.prompt.name], rules['test_setup']);
          final subjects = {for (final a in planned) a.subject.id};
          expect(subjects, hasLength(planned.length));
          expect(subjects, isNot(contains(players[artist].id)));
          seen.addAll(subjects);
        }
      }
      expect(seen, hasLength(n), reason: 'everyone can be drawn');
    }
  });

  test('upgrades', () {
    final upgrades = rules['upgrades'] as Map<String, dynamic>;
    expect({
      for (final r in Rarity.values) r.name: [for (final e in UpgradeTree.pathFor(r)) e.name],
    }, upgrades['paths']);
    expect([for (final e in ElementKind.values) e.name], upgrades['elements']);
  });

  test('fights', () {
    final fights = rules['fights'] as Map<String, dynamic>;
    expect(FightSetup.maxFighters, fights['max_fighters']);
    expect({
      for (final MapEntry(:key, :value) in FightSetup.rarityPower.entries) key.name: value,
    }, fights['rarity_power']);
    expect(FightSetup.upgradePower, fights['upgrade_power']);
    expect(FightSetup.challengerPower, fights['challenger_power']);
  });

  test('themes', () {
    expect([for (final t in DailyTheme.values) t.name], rules['themes']);
    expect(DailyTheme.ofDay(1), DailyTheme.forest);
    expect(DailyTheme.ofDay(DailyTheme.values.length + 2), DailyTheme.beach);
  });

  group('gacha', () {
    final gacha = rules['gacha'] as Map<String, dynamic>;

    test('numbers', () {
      expect(GachaMachine.launchBonus, gacha['launch_bonus']);
      expect({for (final MapEntry(:key, :value) in GachaMachine.rates.entries) key.name: value}, gacha['rates']);
      expect(GachaMachine.beginnerWindow, gacha['beginner_window']);
      expect(GachaMachine.legendPity, gacha['legend_pity']);
    });

    test('tier fallback', () {
      for (final [List available, String wanted, bool guaranteed, String expected] in gacha['tier_fallback'] as List) {
        final tier = GachaMachine.closestAvailableTier(
          {for (final r in available) Rarity.values.byName(r as String)},
          Rarity.values.byName(wanted),
          preferHigher: guaranteed,
        );
        expect(tier.name, expected, reason: '$available, $wanted, $guaranteed');
      }
    });
  });
}
