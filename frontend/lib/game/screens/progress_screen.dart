import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/models.dart';
import '../rules/progress.dart';
import '../widgets/card_art.dart';

/// How far the collection has come: characters collected and maxed out,
/// upgrades unlocked and the duplicates still to go, overall and by rarity.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final byRarity = Progress.byRarity(controller.pool, controller.collection);
        final total = byRarity.values.fold(Progress.empty, (a, b) => a + b);
        final textTheme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Progress')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              _Ring(
                                value: total.owned == 0 ? 0 : total.maxed / total.owned,
                                label: '${total.maxed}/${total.owned}',
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Maxed out', style: textTheme.titleMedium),
                                    const SizedBox(height: 4),
                                    _Fact('Collected', '${total.collected}/${total.inPool}'),
                                    _Fact('Upgrades unlocked', '${total.unlockedSteps}/${total.steps}'),
                                    _Fact('Duplicates to max everything', '${total.duplicatesToMax}'),
                                    _Fact('Spare duplicates', '${total.spareDuplicates}'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final rarity in Rarity.values.reversed)
                        if (byRarity[rarity]!.inPool > 0 || byRarity[rarity]!.owned > 0)
                          _RarityCard(rarity: rarity, progress: byRarity[rarity]!),
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

class _RarityCard extends StatelessWidget {
  const _RarityCard({required this.rarity, required this.progress});

  final Rarity rarity;
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
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
              ],
            ),
            const SizedBox(height: 8),
            _Bar('Collected', progress.collected, progress.inPool, rarity.color),
            _Bar('Upgrades', progress.unlockedSteps, progress.steps, rarity.color),
            _Bar('Maxed out', progress.maxed, progress.owned, rarity.color),
            if (progress.owned > 0)
              Text(
                '${progress.duplicatesToMax} duplicates to max them all · ${progress.spareDuplicates} spare',
                style: textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.done, this.of, this.color);

  final String label;
  final int done;
  final int of;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: textTheme.labelMedium)),
              Text('$done/$of', style: textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: of == 0 ? 0 : done / of,
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: textTheme.bodySmall)),
        Text(value, style: textTheme.labelLarge),
      ],
    );
  }
}

/// A ring filling up as the collection maxes out, counting up when shown.
class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 88,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: value,
              strokeWidth: 8,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            Center(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          ],
        ),
      ),
    );
  }
}
