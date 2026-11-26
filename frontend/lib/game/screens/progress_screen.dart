import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/models.dart';
import '../rules/progress.dart';
import '../widgets/card_art.dart';

/// How far a collection has come: characters collected out of the pool,
/// maxed out, upgrades unlocked and the duplicates still to go, overall and
/// by rarity. Yours by default; a dropdown picks any other player of the
/// server, whose totals load from the server.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  /// The other player shown, or null for you.
  Player? _player;
  Future<Map<Rarity, Progress>>? _theirs;

  void _pick(Player? player) {
    setState(() {
      _player = player == null || player.isYou ? null : player;
      _theirs = switch (_player) {
        final other? => widget.controller.playerProgress(other),
        null => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final players = [
          ...controller.server.players.where((p) => p.isYou),
          ...controller.otherPlayers,
        ];
        final picker = DropdownButtonFormField<String>(
          initialValue: players.firstWhere((p) => p.id == _player?.id, orElse: () => players.first).id,
          decoration: const InputDecoration(labelText: 'Player', border: OutlineInputBorder()),
          isExpanded: true,
          items: [
            for (final player in players)
              DropdownMenuItem(value: player.id, child: Text(player.isYou ? 'You' : player.name)),
          ],
          onChanged: (id) => _pick(players.where((p) => p.id == id).firstOrNull),
        );
        final Widget body = switch (_theirs) {
          null => _ProgressView(byRarity: Progress.byRarity(controller.pool, controller.collection)),
          final theirs => FutureBuilder(
            key: ValueKey(_player?.id),
            future: theirs,
            builder: (context, snapshot) => switch (snapshot) {
              AsyncSnapshot(hasData: true, :final data?) => _ProgressView(byRarity: data),
              AsyncSnapshot(hasError: true) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text("Couldn't load their progress. Try again later.", textAlign: TextAlign.center),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ),
        };
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
                      if (players.length > 1) ...[picker, const SizedBox(height: 12)],
                      body,
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

/// A collection's progress: the total in a card on top, then a card per
/// rarity of the pool or the collection.
class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.byRarity});

  final Map<Rarity, Progress> byRarity;

  @override
  Widget build(BuildContext context) {
    final total = byRarity.values.fold(Progress.empty, (a, b) => a + b);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _Ring(
                  value: total.inPool == 0 ? 0 : total.collected / total.inPool,
                  label: '${total.collected}/${total.inPool}',
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Collected', style: textTheme.titleMedium),
                      const SizedBox(height: 4),
                      _Fact('Maxed out', '${total.maxed}/${total.owned}'),
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
          if (byRarity[rarity] case final progress? when progress.inPool > 0 || progress.owned > 0)
            _RarityCard(rarity: rarity, progress: progress),
      ],
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

/// A ring filling up as the pool gets collected, counting up when shown.
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
