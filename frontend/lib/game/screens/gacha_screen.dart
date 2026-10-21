import 'dart:math';

import 'package:flutter/material.dart';

import '../rules/gacha.dart';
import '../game_session.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/themed_background.dart';
import '../widgets/ticket_chip.dart';
import 'pool_screen.dart';
import 'pull_reveal_screen.dart';

/// Pulls on a banner of your choice: the standard one is always there, the
/// weekly one opens with the first finale.
class GachaScreen extends StatefulWidget {
  const GachaScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<GachaScreen> createState() => _GachaScreenState();
}

class _GachaScreenState extends State<GachaScreen> {
  GameSession get controller => widget.controller;

  GachaBanner? _chosen;

  /// The weekly banner once it's open, unless you chose the standard one.
  GachaBanner get _banner => controller.rateUp.isEmpty ? GachaBanner.standard : _chosen ?? GachaBanner.weekly;

  Future<void> _pull(BuildContext context, int count) async {
    final banner = _banner;
    final outcomes = await runGameQuery(context, () => controller.pull(count, banner: banner));
    if (outcomes == null || !context.mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => PullRevealScreen(outcomes: outcomes),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final gacha = controller.gachaStatus;
        final textTheme = Theme.of(context).textTheme;
        final banner = _banner;
        final weeklyOpen = controller.rateUp.isNotEmpty;
        final pool = banner.poolOf(controller.pool);
        final rates = pool.isEmpty
            ? GachaMachine.rates
            : GachaMachine.tierRates({for (final card in pool) card.rarity});
        return Scaffold(
          appBar: AppBar(
            title: const Text('Summon'),
            actions: [
              TicketChip(tickets: controller.tickets),
              const SizedBox(width: 12),
            ],
          ),
          body: ThemedBackground(
            theme: controller.theme,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        const Center(child: _FloatingCardBack(width: 160)),
                        const SizedBox(height: 32),
                        SegmentedButton<GachaBanner>(
                          segments: [
                            for (final option in GachaBanner.values)
                              ButtonSegment(
                                value: option,
                                label: Text(option.label),
                                enabled: option == GachaBanner.standard || weeklyOpen,
                              ),
                          ],
                          selected: {banner},
                          onSelectionChanged: (selected) => setState(() => _chosen = selected.single),
                        ),
                        const SizedBox(height: 8),
                        Text(switch (banner) {
                          GachaBanner.standard =>
                            'The characters drawn during the setup.'
                                '${weeklyOpen ? '' : ' The weekly banner opens with the first finale.'}',
                          GachaBanner.weekly => 'The whole pool, weekly heroes included, with this week\'s rate-up.',
                        }, style: textTheme.bodySmall),
                        const SizedBox(height: 16),
                        if (banner == GachaBanner.weekly) ...[
                          _RateUpBanner(controller: controller),
                          const SizedBox(height: 16),
                        ],
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rates', style: textTheme.titleMedium),
                                const SizedBox(height: 8),
                                for (final MapEntry(key: rarity, value: rate) in rates.entries)
                                  Row(
                                    children: [
                                      StarRow(rarity: rarity),
                                      const SizedBox(width: 8),
                                      Text(rarity.label),
                                      const Spacer(),
                                      Text('$rate%'),
                                    ],
                                  ),
                                const Divider(height: 24),
                                if (banner == GachaBanner.standard && gacha.beginnerPullsLeft != null)
                                  Text('★★★★ guaranteed within your next ${gacha.beginnerPullsLeft} standard pulls'),
                                Text('★★★★ guaranteed within ${gacha.pullsUntilLegend} pulls on either banner'),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => PoolScreen(controller: controller, banner: banner),
                                      ),
                                    ),
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text('See what you can pull'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: controller.tickets >= 1 ? () => _pull(context, 1) : null,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Pull ×1'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: controller.tickets >= 10 ? () => _pull(context, 10) : null,
                                icon: const Icon(Icons.auto_awesome_rounded),
                                label: const Text('Pull ×10'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FloatingCardBack extends StatefulWidget {
  const _FloatingCardBack({required this.width});

  final double width;

  @override
  State<_FloatingCardBack> createState() => _FloatingCardBackState();
}

class _FloatingCardBackState extends State<_FloatingCardBack> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * pi;
        return Transform.translate(
          offset: Offset(0, sin(t) * 8),
          child: Transform.rotate(angle: sin(t) * 0.04, child: child),
        );
      },
      child: CardBack(width: widget.width),
    );
  }
}

/// This week's rate-up characters, with each one's chance per pull.
class _RateUpBanner extends StatelessWidget {
  const _RateUpBanner({required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rateUp = controller.rateUp;
    final featured = [
      for (final card in controller.pool)
        if (rateUp.contains(card.id)) card,
    ]..sort((a, b) => b.rarity.stars.compareTo(a.rarity.stars));
    final owned = {for (final o in controller.collection) o.card.id};
    final chances = GachaMachine.characterChances(controller.pool, rateUp);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rate up this week', style: textTheme.titleMedium),
            Text(
              'When a pull lands on their rarity, it\'s one of them ${GachaMachine.rateUp}% of the time, or every '
              'time if they\'re the only one. A new weekly hero takes over every Monday.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final card in featured)
                  SizedBox(
                    width: 96,
                    child: Column(
                      children: [
                        // Everyone saw the weekly hero in the finale; other
                        // characters stay hidden until summoned.
                        Standee(
                          card: card,
                          width: 84,
                          hidden: !owned.contains(card.id) && card.id != controller.weeklyHero?.card.id,
                        ),
                        StarRow(rarity: card.rarity, size: 14),
                        Text(card.subject, style: textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          card.title,
                          style: textTheme.labelSmall,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('${percent(chances[card.id]!)} per pull', style: textTheme.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
