import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../widgets/card_art.dart';

/// The challengers you encountered (drew, fought against or boosted) with
/// their win rates. Challengers don't join the gacha pool.
class ChallengersScreen extends StatelessWidget {
  const ChallengersScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final challengers = controller.challengers;
        return Scaffold(
          appBar: AppBar(title: const Text('Challengers')),
          body: challengers.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No challengers yet. Draw one, fight one or boost one to meet them.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    // Room for titles on two lines.
                    mainAxisExtent: 336,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: challengers.length,
                  itemBuilder: (context, index) => _ChallengerTile(record: challengers[index]),
                ),
        );
      },
    );
  }
}

class _ChallengerTile extends StatelessWidget {
  const _ChallengerTile({required this.record});

  final ChallengerRecord record;

  /// E.g. "Won 2 of 3 · 67%".
  static String recordLabel(ChallengerRecord record) => switch (record.winRate) {
    null => 'No fights decided yet',
    final rate => 'Won ${record.wins} of ${record.fights} · ${(rate * 100).round()}%',
  };

  @override
  Widget build(BuildContext context) {
    final card = record.card;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Standee(card: card, width: 120),
        const SizedBox(height: 6),
        Nameplate(name: card.subject, title: card.title, rarity: card.rarity, compact: true),
        const SizedBox(height: 4),
        Text(recordLabel(record), style: text.labelMedium, textAlign: TextAlign.center),
        Text('Day ${card.day} · by ${card.artist}', style: text.labelSmall, textAlign: TextAlign.center),
      ],
    );
  }
}
