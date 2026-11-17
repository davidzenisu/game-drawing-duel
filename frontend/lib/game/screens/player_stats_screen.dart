import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../widgets/game_action.dart';

/// How every player did, a stat at a time: this week so far, last week
/// (whose first places got stars) or all time. Pick a stat to see every
/// player ranked by it.
class PlayerStatsScreen extends StatefulWidget {
  const PlayerStatsScreen({super.key, required this.controller, this.period = StatPeriod.week});

  final GameSession controller;

  /// The period shown first.
  final StatPeriod period;

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
  late StatPeriod _period = widget.period;
  PlayerStatKind _kind = PlayerStatKind.starsEarned;
  final Map<StatPeriod, PlayerStats?> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// The [_period]'s stats: last week's as kept on the device, unless
  /// [refresh].
  Future<void> _load({bool refresh = false}) async {
    final period = _period;
    setState(() => _loading = true);
    final stats = await runGameQuery(context, () => widget.controller.playerStats(period, refresh: refresh));
    if (!mounted) return;
    setState(() {
      if (stats != null || !refresh) _stats[period] = stats;
      _loading = false;
    });
  }

  void _pick(StatPeriod period) {
    setState(() => _period = period);
    if (!_stats.containsKey(period)) _load();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats[_period];
    final loaded = _stats.containsKey(_period);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player stats'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _load(refresh: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<StatPeriod>(
                    segments: [
                      for (final period in StatPeriod.values) ButtonSegment(value: period, label: Text(period.label)),
                    ],
                    selected: {_period},
                    showSelectedIcon: false,
                    onSelectionChanged: (picked) => _pick(picked.single),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in PlayerStatKind.values)
                        ChoiceChip(
                          label: Text(kind.label),
                          selected: kind == _kind,
                          onSelected: (_) => setState(() => _kind = kind),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!loaded || (_loading && stats == null))
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (stats == null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _period == StatPeriod.lastWeek
                            ? 'No finished week yet. Once the first week is over, its stats show here.'
                            : 'No player stats in this session.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else ...[
                    Text(_span(stats), style: text.bodyMedium),
                    const SizedBox(height: 12),
                    if (stats.stats.where((s) => s.kind == _kind).firstOrNull case final stat?)
                      StatLeaderboard(stat: stat, rewardStars: stats.rewardStars),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _span(PlayerStats stats) {
    final days = stats.fromDay == stats.toDay ? 'Day ${stats.toDay}' : 'Days ${stats.fromDay} to ${stats.toDay}';
    return switch (stats.period) {
      StatPeriod.week => '$days, so far. Once the week is over, every first place gets ${StarRewards.weekStat} ★.',
      StatPeriod.lastWeek => '$days. Every first place got ${stats.rewardStars} ★ as a gift.',
      StatPeriod.all => '$days: every day since the start.',
    };
  }
}

/// Every player ranked by [stat], best first: tied players share a place.
/// First places wear a trophy, and your row stands out.
class StatLeaderboard extends StatelessWidget {
  const StatLeaderboard({super.key, required this.stat, this.rewardStars = 0});

  final PlayerStat stat;

  /// The stars each first place got, if any.
  final int rewardStars;

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
                      child: placed.place == 1 && placed.value > 0
                          ? const Icon(Icons.emoji_events_rounded, color: AppPalette.rarityHero, semanticLabel: '1')
                          : Text('${placed.place}', style: text.titleMedium, textAlign: TextAlign.center),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        placed.player.isYou ? '${placed.player.name} (you)' : placed.player.name,
                        style: text.bodyLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (rewardStars > 0 && placed.place == 1 && placed.value > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('+$rewardStars ★', style: text.labelMedium?.copyWith(color: AppPalette.rarityHero)),
                      ),
                    Text('${placed.value} ${kind.unit}', style: text.titleSmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
