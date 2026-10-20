import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/gacha.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';

/// Formats a chance in percent: whole numbers as they are, small ones with
/// enough decimals to tell them apart.
String _percent(double value) {
  if (value == value.roundToDouble()) return '${value.round()}%';
  return '${value.toStringAsFixed(value < 1 ? 2 : 1)}%';
}

/// What a pull can bring: the pool's characters by rarity, each rarity's
/// chance and each character's. Characters you haven't summoned yet show
/// only their name, like in the collection.
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
                        'all equally likely.',
                        style: textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      for (final rarity in Rarity.values.reversed)
                        if (byRarity[rarity]!.isNotEmpty)
                          _RaritySection(
                            rarity: rarity,
                            cards: byRarity[rarity]!,
                            rate: rates[rarity] ?? 0,
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
    required this.owned,
    required this.weeklyHeroId,
  });

  final Rarity rarity;
  final List<CharacterCard> cards;
  final int rate;
  final Set<String> owned;
  final String? weeklyHeroId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summoned = cards.where((card) => owned.contains(card.id)).length;
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
              '${cards.length} character${cards.length == 1 ? '' : 's'} · ${_percent(rate / cards.length)} each · '
              '$summoned/${cards.length} summoned',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  _PoolTile(card: card, summoned: owned.contains(card.id), weeklyHero: card.id == weeklyHeroId),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PoolTile extends StatelessWidget {
  const _PoolTile({required this.card, required this.summoned, required this.weeklyHero});

  final CharacterCard card;
  final bool summoned;
  final bool weeklyHero;

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
          if (weeklyHero)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Weekly hero',
                style: textTheme.labelSmall?.copyWith(color: card.rarity.color, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
