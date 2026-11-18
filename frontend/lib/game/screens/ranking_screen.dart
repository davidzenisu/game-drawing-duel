import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/sketch_canvas.dart';
import 'player_stats_view.dart';
import 'ranking_detail_screen.dart';

/// Who sees the week ranking: the players' stats or the challengers.
enum RankingView {
  players('Players'),
  challengers('Challengers');

  const RankingView(this.label);

  final String label;
}

/// The week ranking, of this week so far or last week, in two views:
///
/// - **Players** (the default, this week): every player ranked in the
///   player stats' categories (`PlayerStatsView`), this week's boosts kept
///   secret.
/// - **Challengers**: this week, only who its challengers portray, as a pie;
///   last week, the pie and its challengers ranked by their stars, the first
///   the weekly hero. Tapping one opens its details.
///
/// Answers are kept on the device: this week's for the day, last week's
/// until the next week is over; the refresh button asks again.
class RankingScreen extends StatefulWidget {
  const RankingScreen({
    super.key,
    required this.controller,
    this.view = RankingView.players,
    this.period = StatPeriod.week,
  });

  final GameSession controller;

  /// The view and week shown first.
  final RankingView view;
  final StatPeriod period;

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  late RankingView _view = widget.view;
  late StatPeriod _period = widget.period;
  final Map<StatPeriod, PlayerStats?> _stats = {};
  WeekRanking? _ranking;
  bool _rankingLoaded = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Last week's challengers come from the week ranking, everything else
  /// from the player stats.
  bool get _showsRanking => _view == RankingView.challengers && _period == StatPeriod.lastWeek;

  bool get _loaded => _showsRanking ? _rankingLoaded : _stats.containsKey(_period);

  /// What the current view and week show: as kept on the device, unless
  /// [refresh].
  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    final controller = widget.controller;
    if (_showsRanking) {
      final ranking = await runGameQuery(context, () => controller.weekRanking(refresh: refresh));
      if (!mounted) return;
      setState(() {
        if (ranking != null || !refresh) _ranking = ranking;
        _rankingLoaded = true;
        _loading = false;
      });
    } else {
      final period = _period;
      final stats = await runGameQuery(context, () => controller.playerStats(period, refresh: refresh));
      if (!mounted) return;
      setState(() {
        if (stats != null || !refresh) _stats[period] = stats;
        _loading = false;
      });
    }
  }

  void _show({RankingView? view, StatPeriod? period}) {
    setState(() {
      _view = view ?? _view;
      _period = period ?? _period;
    });
    if (!_loaded) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Week ranking'),
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
                  SegmentedButton<RankingView>(
                    segments: [
                      for (final view in RankingView.values)
                        ButtonSegment(
                          value: view,
                          label: Text(view.label),
                          icon: Icon(view == RankingView.players ? Icons.people_alt_rounded : Icons.shield_rounded),
                        ),
                    ],
                    selected: {_view},
                    showSelectedIcon: false,
                    onSelectionChanged: (picked) => _show(view: picked.single),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<StatPeriod>(
                    segments: [
                      for (final period in StatPeriod.values) ButtonSegment(value: period, label: Text(period.label)),
                    ],
                    selected: {_period},
                    showSelectedIcon: false,
                    onSelectionChanged: (picked) => _show(period: picked.single),
                  ),
                  const SizedBox(height: 16),
                  if (!_loaded || (_loading && _content(context) == null))
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    _content(context) ??
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _period == StatPeriod.lastWeek
                                ? 'No ranking yet. Once the first week is over, it shows here.'
                                : 'Nothing to rank in this session.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the current view and week show; null without anything to show.
  Widget? _content(BuildContext context) {
    final players = widget.controller.server.players;
    if (_showsRanking) {
      final ranking = _ranking;
      if (ranking == null || ranking.challengers.isEmpty) return null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Week ${widget.controller.weekOf(ranking.day)}: ${ranking.challengers.length} challengers, ranked by '
            'their own ${Stars.challengerBase} ★ plus their boost stars.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          PlayersDashboard(weeks: PlayerWeek.ofRanking(players, ranking)),
          const SizedBox(height: 12),
          _WinnerCard(entry: ranking.challengers.first),
          const SizedBox(height: 8),
          for (final (i, entry) in ranking.challengers.indexed.skip(1)) _RankTile(place: i + 1, entry: entry),
        ],
      );
    }
    final stats = _stats[_period];
    if (stats == null) return null;
    final week = widget.controller.weekOf(stats.toDay);
    if (_view == RankingView.players) return PlayerStatsView(key: ValueKey(_period), stats: stats, week: week);
    final total = stats.portrayed.fold(0, (sum, p) => sum + p.$2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Week $week, so far: $total challengers drawn for this week. '
          'Their stars stay secret until the week is over; then they are ranked.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        PlayersDashboard(weeks: PlayerWeek.of(players, {for (final (player, n) in stats.portrayed) player.name: n})),
      ],
    );
  }
}

void _openDetails(BuildContext context, int place, RankedChallenger entry) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => RankingDetailScreen(place: place, entry: entry),
  ),
);

/// How often a player was chosen as a challenger in a week: the challengers
/// portraying them.
class PlayerWeek {
  const PlayerWeek({required this.name, required this.position, required this.chosen});

  final String name;

  /// Their place in the roster, which picks their color.
  final int position;
  final int chosen;

  /// Every player of the roster, most [chosen] (by name) first.
  static List<PlayerWeek> of(List<Player> players, Map<String, int> chosen) {
    final entries = [
      for (final (position, player) in players.indexed)
        PlayerWeek(name: player.name, position: position, chosen: chosen[player.name] ?? 0),
    ];
    return entries..sort((a, b) {
      final byChosen = b.chosen.compareTo(a.chosen);
      return byChosen != 0 ? byChosen : a.position.compareTo(b.position);
    });
  }

  /// Every player of the roster, with the challengers of [ranking]
  /// portraying them.
  static List<PlayerWeek> ofRanking(List<Player> players, WeekRanking ranking) {
    final chosen = <String, int>{};
    for (final entry in ranking.challengers) {
      chosen[entry.card.subject] = (chosen[entry.card.subject] ?? 0) + 1;
    }
    return of(players, chosen);
  }
}

/// The week at a glance: a pie of how often each player was chosen as a
/// challenger, with a legend of every player, their count and share.
///
/// Each player keeps their color by roster position, from ten validated
/// categorical hues (stepped for dark mode), one for every player of a full
/// roster. Slices are split by a thin gap of the card's color.
class PlayersDashboard extends StatelessWidget {
  const PlayersDashboard({super.key, required this.weeks});

  /// Every player, most chosen first ([PlayerWeek.of]).
  final List<PlayerWeek> weeks;

  /// One hue for each of the most players a server takes (ten).
  static const _light = [
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
    Color(0xFFE87BA4),
    Color(0xFF008300),
    Color(0xFF6250D6),
    Color(0xFFE34948),
    Color(0xFF8A2B60),
    Color(0xFF1EB7EE),
  ];
  static const _dark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF0CA30C),
    Color(0xFF9085E9),
    Color(0xFFE66767),
    Color(0xFFA738A2),
    // Lighter than the others: a darker cyan reads as the blue or violet.
    Color(0xFF27C0DC),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final hues = theme.brightness == Brightness.dark ? _dark : _light;
    // Past a full roster, which can't happen, players share the last hue.
    Color colorOf(PlayerWeek week) => hues[math.min(week.position, hues.length - 1)];

    final total = weeks.fold(0, (sum, w) => sum + w.chosen);
    final slices = <(Color, int)>[
      for (final week in weeks)
        if (week.chosen > 0) (colorOf(week), week.chosen),
    ];
    final cardColor = theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow;

    final pie = Semantics(
      label: [for (final w in weeks) '${w.name} ${w.chosen}'].join(', '),
      child: SizedBox.square(
        dimension: 132,
        child: CustomPaint(
          painter: _PiePainter(slices: slices, gap: cardColor),
        ),
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final week in weeks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: colorOf(week), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Text(week.name, style: text.labelLarge, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text(
                  '${week.chosen}${total == 0 ? '' : ' · ${(100 * week.chosen / total).round()}%'}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
    return Card(
      // The same color as the gaps between the slices.
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Chosen as challenger', style: text.titleMedium),
            Text("How many of the week's challengers portray each player", style: text.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 24,
              runSpacing: 12,
              children: [pie, legend],
            ),
          ],
        ),
      ),
    );
  }
}

/// A pie of [slices] (color and value), clockwise from the top, each split
/// from the next by a [gap] colored line.
class _PiePainter extends CustomPainter {
  const _PiePainter({required this.slices, required this.gap});

  final List<(Color, int)> slices;
  final Color gap;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold(0, (sum, s) => sum + s.$2);
    if (total == 0) return;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;
    var start = -math.pi / 2;
    final edges = <double>[];
    for (final (color, value) in slices) {
      final sweep = 2 * math.pi * value / total;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = color);
      edges.add(start);
      start += sweep;
    }
    if (slices.length < 2) return;
    final line = Paint()
      ..color = gap
      ..strokeWidth = 2;
    for (final angle in edges) {
      canvas.drawLine(center, center + Offset(math.cos(angle), math.sin(angle)) * radius, line);
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.slices != slices || old.gap != gap;
}

/// The weekly hero, first and bigger than the others: its drawing large,
/// its nameplate and its stars, in a hero-gold frame.
class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.entry});

  final RankedChallenger entry;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final text = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.rarityHero, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetails(context, 1, entry),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.emoji_events_rounded, color: AppPalette.rarityHero),
                  const SizedBox(width: 6),
                  Text('#1 · Weekly hero', style: text.titleMedium?.copyWith(color: AppPalette.rarityHero)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(width: 160, child: CardboardCard(child: SketchView(card.sketch))),
              const SizedBox(height: 12),
              Nameplate(name: card.subject, title: card.title, rarity: card.rarity),
              const SizedBox(height: 8),
              Text('${entry.stars} ★', style: text.headlineSmall?.copyWith(color: AppPalette.rarityHero)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({required this.place, required this.entry});

  final int place;
  final RankedChallenger entry;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final textTheme = Theme.of(context).textTheme;
    final hero = place == 1;
    return Card(
      shape: hero
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppPalette.rarityHero, width: 2),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RankingDetailScreen(place: place, entry: entry),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text('$place', style: textTheme.titleMedium, textAlign: TextAlign.center),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 44, child: CardboardCard(child: SketchView(card.sketch))),
              const SizedBox(width: 8),
              Expanded(
                child: Nameplate(name: card.subject, title: card.title, rarity: card.rarity, compact: true),
              ),
              const SizedBox(width: 12),
              Text(
                '${entry.stars} ★',
                style: textTheme.titleMedium?.copyWith(color: hero ? AppPalette.rarityHero : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
