import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/daily_loop.dart';

/// How every player did in [week], a category at a time: chips, wrapping
/// onto more lines where the screen is too narrow, pick the category, whose
/// players are ranked below with the trophies they won in it. Each
/// category's first places win a trophy once the week is over.
class PlayerStatsView extends StatefulWidget {
  const PlayerStatsView({super.key, required this.stats, required this.week});

  final PlayerStats stats;

  /// The number of the week the stats count, see `GameSession.weekOf`.
  final int week;

  @override
  State<PlayerStatsView> createState() => _PlayerStatsViewState();
}

class _PlayerStatsViewState extends State<PlayerStatsView> {
  PlayerStatKind _kind = PlayerStatKind.mostWins;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_span(stats, widget.week), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in PlayerStatKind.values)
              ChoiceChip(
                label: Text(kind.label),
                selected: _kind == kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (stats.stats.where((s) => s.kind == _kind).firstOrNull case final stat?)
          StatLeaderboard(stat: stat, over: stats.period == StatPeriod.lastWeek),
      ],
    );
  }

  static String _span(PlayerStats stats, int week) => switch (stats.period) {
    StatPeriod.week =>
      'Week $week, so far. Once the week is over, the first place of each category wins a trophy worth '
          '${stats.trophyStars} ★.',
    StatPeriod.lastWeek => 'Week $week. The first place of each category won a trophy worth ${stats.trophyStars} ★.',
  };
}

/// Every player ranked by [stat], best first, without place numbers: the
/// first places wear a trophy, filled once the week is [over] and they won
/// it, an outline while it's still to win. Your row stands out, and every
/// player shows the trophies they won in it so far. A secret stat shows only
/// those.
class StatLeaderboard extends StatelessWidget {
  const StatLeaderboard({super.key, required this.stat, this.over = false});

  final PlayerStat stat;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final kind = stat.kind;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind.label, style: text.titleMedium),
                  Text(kind.description, style: text.bodySmall),
                  if (stat.secret) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.lock_rounded, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Secret until the week is over: it would tell how strong this week's drawings are.",
                            style: text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final placed in stat.players)
              Container(
                color: placed.player.isYou ? theme.colorScheme.primaryContainer : null,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: placed.first
                          ? Icon(
                              over ? Icons.emoji_events_rounded : Icons.emoji_events_outlined,
                              key: const ValueKey('first-place'),
                              color: AppPalette.rarityHero,
                              semanticLabel: over ? 'Trophy won' : 'First so far',
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        placed.player.isYou ? '${placed.player.name} (you)' : placed.player.name,
                        style: text.bodyLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (placed.trophies > 0)
                      Tooltip(
                        message: '${placed.trophies} ${placed.trophies == 1 ? 'trophy' : 'trophies'} won',
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.emoji_events_rounded, size: 16, color: AppPalette.rarityHero),
                              Text('×${placed.trophies}', style: text.labelMedium),
                            ],
                          ),
                        ),
                      ),
                    if (placed.value case final value?) Text('$value ${kind.unit}', style: text.titleSmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
