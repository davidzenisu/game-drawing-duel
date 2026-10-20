import 'dart:math';

import 'package:flutter/material.dart';

import '../rules/gacha.dart';
import '../game_session.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/themed_background.dart';
import '../widgets/ticket_chip.dart';
import 'pull_reveal_screen.dart';

class GachaScreen extends StatelessWidget {
  const GachaScreen({super.key, required this.controller});

  final GameSession controller;

  Future<void> _pull(BuildContext context, int count) async {
    final outcomes = await runGameQuery(context, () => controller.pull(count));
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
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rates', style: textTheme.titleMedium),
                                const SizedBox(height: 8),
                                for (final MapEntry(key: rarity, value: rate) in GachaMachine.rates.entries)
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
                                if (gacha.beginnerPullsLeft != null)
                                  Text('★★★ or better guaranteed within the next ${gacha.beginnerPullsLeft} pulls'),
                                Text('★★★★ guaranteed within ${gacha.pullsUntilLegend} pulls'),
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
