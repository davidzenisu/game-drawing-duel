import 'dart:math';

import 'models.dart';

class FighterStats {
  const FighterStats({required this.attack, required this.maxHp});

  /// Stats grow with rarity and every unlocked upgrade.
  factory FighterStats.of(Rarity rarity, {int upgrades = 0}) {
    final attack =
        switch (rarity) {
          Rarity.basic => 10,
          Rarity.adventurer => 13,
          Rarity.hero => 16,
          Rarity.legend => 21,
        } +
        upgrades * 2;
    return FighterStats(attack: attack, maxHp: 60 + attack * 3);
  }

  final int attack;
  final int maxHp;
}

class DuelHit {
  const DuelHit({
    required this.byLeft,
    required this.damage,
    required this.critical,
    required this.leftHp,
    required this.rightHp,
  });

  final bool byLeft;
  final int damage;
  final bool critical;
  final int leftHp;
  final int rightHp;
}

class DuelResult {
  const DuelResult(this.hits, {required this.leftWins});

  final List<DuelHit> hits;
  final bool leftWins;
}

/// Simulates an automatic fight up front so the UI can replay it.
abstract final class Duel {
  static const maxRounds = 40;
  static const criticalChance = 0.2;

  static DuelResult simulate(FighterStats left, FighterStats right, {Random? random}) {
    final rng = random ?? Random();
    var leftHp = left.maxHp;
    var rightHp = right.maxHp;
    var leftTurn = rng.nextBool();
    final hits = <DuelHit>[];

    while (leftHp > 0 && rightHp > 0 && hits.length < maxRounds) {
      final attacker = leftTurn ? left : right;
      final critical = rng.nextDouble() < criticalChance;
      var damage = (attacker.attack * (0.5 + rng.nextDouble())).round();
      if (critical) damage = (damage * 1.8).round();
      if (leftTurn) {
        rightHp = max(0, rightHp - damage);
      } else {
        leftHp = max(0, leftHp - damage);
      }
      hits.add(DuelHit(byLeft: leftTurn, damage: damage, critical: critical, leftHp: leftHp, rightHp: rightHp));
      leftTurn = !leftTurn;
    }

    final leftWins = rightHp == 0 || (leftHp > 0 && leftHp / left.maxHp >= rightHp / right.maxHp);
    return DuelResult(hits, leftWins: leftWins);
  }
}
