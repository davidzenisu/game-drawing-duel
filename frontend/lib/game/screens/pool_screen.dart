import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/gacha.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';

/// Formats a chance in percent: whole numbers as they are, small ones with
/// enough decimals to tell them apart.
String percent(double value) {
  if (value == value.roundToDouble()) return '${value.round()}%';
  return '${value.toStringAsFixed(value < 1 ? 2 : 1)}%';
}

/// What a pull can bring: the pool's characters by rarity, each rarity's
/// chance and each character's, with this week's rate-up marked.
/// Characters you haven't summoned yet show only their name, like in the
/// collection.
class PoolScreen extends StatelessWidget {
  const PoolScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pool = controller.pool;
        final owned = {for (final o in controller.collection) o.card.id};
        final byRarity = {
          for (final rarity in Rarity.values)
            rarity: [
              for (final card in pool)
                if (card.rarity == rarity) card,
            ],
        };
        final rates = GachaMachine.tierRates({for (final card in pool) card.rarity});
        final rateUp = controller.rateUp;
        final chances = GachaMachine.characterChances(pool, rateUp);
        final textTheme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('In the pool')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${pool.length} characters. Each pull picks a rarity, then one of its characters, '
                        'all equally likely${rateUp.isEmpty ? '' : ' but this week\'s rate-up, which get '
                                  '${GachaMachine.rateUp}% of their rarity between them'}.',
                        style: textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      for (final rarity in Rarity.values.reversed)
                        if (byRarity[rarity]!.isNotEmpty)
                          _RaritySection(
                            rarity: rarity,
                            cards: byRarity[rarity]!,
                            rate: rates[rarity] ?? 0,
                            chances: chances,
                            rateUp: rateUp,
                            owned: owned,
                            weeklyHeroId: controller.weeklyHero?.card.id,
                          )
                        else if (pool.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              'No ${rarity.label} characters yet: their ${GachaMachine.rates[rarity]}% goes to the '
                              '${GachaMachine.closestAvailableTier(rates.keys.toSet(), rarity, preferHigher: false).label} '
                              'ones.',
                              style: textTheme.bodySmall,
                            ),
                          ),
                      Text(
                        'Chances before guarantees: a ${'★' * Rarity.hero.stars} or better within your first '
                        '${GachaMachine.beginnerWindow} pulls, and a ${'★' * Rarity.legend.stars} at the latest every '
                        '${GachaMachine.legendPity}.',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RaritySection extends StatelessWidget {
  const _RaritySection({
    required this.rarity,
    required this.cards,
    required this.rate,
    required this.chances,
    required this.rateUp,
    required this.owned,
    required this.weeklyHeroId,
  });

  final Rarity rarity;
  final List<CharacterCard> cards;
  final int rate;
  final Map<String, double> chances;
  final Set<String> rateUp;
  final Set<String> owned;
  final String? weeklyHeroId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summoned = cards.where((card) => owned.contains(card.id)).length;
    final featured = [
      for (final card in cards)
        if (rateUp.contains(card.id)) card,
    ];
    final others = [
      for (final card in cards)
        if (!rateUp.contains(card.id)) card,
    ];
    final each = featured.isEmpty || others.isEmpty
        ? '${percent(chances[cards.first.id]!)} each'
        : 'rate-up ${percent(chances[featured.first.id]!)}, '
              'the other${others.length == 1 ? '' : 's'} ${percent(chances[others.first.id]!)} each';
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StarRow(rarity: rarity),
                const SizedBox(width: 8),
                Text(rarity.label, style: textTheme.titleMedium),
                const Spacer(),
                Text('$rate%', style: textTheme.titleMedium?.copyWith(color: rarity.color)),
              ],
            ),
            Text(
              '${cards.length} character${cards.length == 1 ? '' : 's'} · $each · '
              '$summoned/${cards.length} summoned',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  _PoolTile(
                    card: card,
                    summoned: owned.contains(card.id),
                    weeklyHero: card.id == weeklyHeroId,
                    rateUp: rateUp.contains(card.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PoolTile extends StatelessWidget {
  const _PoolTile({required this.card, required this.summoned, required this.weeklyHero, required this.rateUp});

  final CharacterCard card;
  final bool summoned;
  final bool weeklyHero;
  final bool rateUp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          Standee(card: card, width: 76, hidden: !summoned),
          const SizedBox(height: 4),
          Text(card.subject, style: textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            summoned ? card.title : '???',
            style: textTheme.labelSmall,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          for (final label in [if (weeklyHero) 'Weekly hero', if (rateUp) 'Rate up'])
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: textTheme.labelSmall?.copyWith(color: card.rarity.color, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
