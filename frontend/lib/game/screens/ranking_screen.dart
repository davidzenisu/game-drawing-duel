import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../rules/themes.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/sketch_canvas.dart';
import 'player_stats_view.dart';
import 'ranking_detail_screen.dart';

/// Who sees the week ranking: the players' stats, the challengers or the
/// Arena.
enum RankingView {
  players('Players'),
  challengers('Challengers'),
  arena('Arena');

  const RankingView(this.label);

  final String label;
}

/// The week ranking, of this week so far or last week, in two views:
///
/// - **Players** (the default, this week): every player ranked in the
///   player stats' categories (`PlayerStatsView`), this week's boosts kept
///   secret.
/// - **Challengers**: this week, only who its challengers portray, as a pie;
///   last week, the boost balance its fights gave this week, the pie, its
///   weekly heroes on big cards framed in their rarity's colour, then its
///   other challengers ranked by their stars. Tapping one opens its details.
/// - **Arena**: this week, which challengers are in the Arena, their
///   ratings kept secret; last week, the latest decided Arena: its winners
///   on big cards, then the others with their records.
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
  ArenaRanking? _arena;
  bool _arenaLoaded = false;
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

  /// The latest decided Arena; this week's Arena comes with the day.
  bool get _showsArena => _view == RankingView.arena && _period == StatPeriod.lastWeek;

  bool get _loaded => switch (_view) {
    RankingView.arena => _period == StatPeriod.week || _arenaLoaded,
    _ when _showsRanking => _rankingLoaded,
    _ => _stats.containsKey(_period),
  };

  /// What the current view and week show: as kept on the device, unless
  /// [refresh].
  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    final controller = widget.controller;
    if (_view == RankingView.arena) {
      final arena = _showsArena ? await runGameQuery(context, () => controller.arenaRanking(refresh: refresh)) : null;
      if (!mounted) return;
      setState(() {
        if (arena != null || !refresh) _arena = arena ?? _arena;
        if (_showsArena) _arenaLoaded = true;
        _loading = false;
      });
    } else if (_showsRanking) {
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
                          icon: Icon(switch (view) {
                            RankingView.players => Icons.people_alt_rounded,
                            RankingView.challengers => Icons.shield_rounded,
                            RankingView.arena => Icons.stadium_rounded,
                          }),
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
                            switch (_view) {
                              RankingView.arena when widget.controller.server.isSpeed => 'Speed mode has no Arena.',
                              RankingView.arena =>
                                'No Arena decided yet. The first one opens once the first week is over, and is '
                                    'decided a week later.',
                              _ when _period == StatPeriod.lastWeek =>
                                'No ranking yet. Once the first week is over, it shows here.',
                              _ => 'Nothing to rank in this session.',
                            },
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
    if (_view == RankingView.arena) return _arenaContent(context);
    if (_showsRanking) {
      final ranking = _ranking;
      if (ranking == null || ranking.challengers.isEmpty) return null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Week ${widget.controller.weekOf(ranking.day)}: ${ranking.challengers.length} challengers, ranked by '
            'their boost stars, then the boost stars of their artist\'s challengers, their win rate and the '
            'latest day. The top ${Finale.maxHeroes} became weekly heroes: ★★★★, ★★★ and ★★.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (ranking.boostBalance case final balance?) ...[
            const SizedBox(height: 12),
            BoostBalanceCard(balance: balance),
          ],
          const SizedBox(height: 12),
          PlayersDashboard(weeks: PlayerWeek.ofRanking(players, ranking)),
          const SizedBox(height: 12),
          for (final hero in ranking.heroes) ...[
            _HeroCard(entry: hero, dayTheme: widget.controller.themeOfDay(hero.card.day)),
            const SizedBox(height: 8),
          ],
          for (final entry in ranking.challengers)
            if (!entry.isWeeklyHero) _RankTile(entry: entry, dayTheme: widget.controller.themeOfDay(entry.card.day)),
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

extension on _RankingScreenState {
  /// This week's Arena, or the latest decided one; null without one.
  Widget? _arenaContent(BuildContext context) {
    final controller = widget.controller;
    final textTheme = Theme.of(context).textTheme;
    if (!_showsArena) {
      final status = controller.arena;
      if (status == null) return null;
      return Text(
        "Week ${controller.weekOf(status.week)}'s ${status.challengers} challengers are in the Arena until Sunday, "
        "all but that week's weekly heroes. Their ratings stay secret until the Arena is decided on Monday; then "
        'the top ${Arena.maxWinners} become Arena winners.',
        style: textTheme.bodyMedium,
      );
    }
    final arena = _arena;
    if (arena == null || arena.challengers.isEmpty) return null;
    final unranked = [
      for (final entry in arena.challengers)
        if (!entry.qualified) entry,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "The Arena of week ${controller.weekOf(arena.week)}'s challengers, voted on in week "
          '${controller.weekOf(arena.endsOn)}: ${arena.challengers.length} challengers, ranked by everyone\'s votes, '
          'the ones with at least ${arena.minMatchups} matchups. '
          '${arena.winners.isEmpty ? '' : 'The top ${Arena.maxWinners} became Arena winners: '
                    '${[for (final r in Arena.rarities) '★' * r.stars].join(', ')}.'}',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (arena.winners.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.how_to_vote_outlined),
              title: const Text('Not enough votes: nobody was crowned this week.'),
              subtitle: Text('No challenger took part in ${arena.minMatchups} matchups.'),
            ),
          ),
        for (final winner in arena.winners) ...[
          _ArenaWinnerCard(entry: winner),
          const SizedBox(height: 8),
        ],
        for (final entry in arena.challengers)
          if (!entry.isWinner && entry.qualified) _ArenaTile(entry: entry),
        if (unranked.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Not enough matchups', style: textTheme.titleMedium),
          Text(
            'They took part in fewer than ${arena.minMatchups} matchups, so they weren\'t ranked.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          for (final entry in unranked) _ArenaTile(entry: entry, minMatchups: arena.minMatchups),
        ],
      ],
    );
  }
}

/// An Arena winner, before and bigger than the other challengers, framed
/// in the colour of the rarity it was crowned with.
class _ArenaWinnerCard extends StatelessWidget {
  const _ArenaWinnerCard({required this.entry});

  final ArenaRanked entry;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final text = Theme.of(context).textTheme;
    final rarity = entry.winnerRarity!;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: rarity.color, width: 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.stadium_rounded, color: rarity.color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '#${entry.place} · Arena winner · ${'★' * rarity.stars}',
                    style: text.titleMedium?.copyWith(color: rarity.color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(width: 160, child: CardboardCard(child: SketchView(card.sketch))),
            const SizedBox(height: 12),
            Nameplate(name: card.subject, title: card.title, rarity: card.rarity),
            const SizedBox(height: 4),
            Text('Drawn by ${card.artist}', style: text.bodySmall),
            const SizedBox(height: 8),
            Text('Won ${entry.record} matchups', style: text.titleMedium?.copyWith(color: rarity.color)),
          ],
        ),
      ),
    );
  }
}

/// A challenger of a decided Arena in a row: its place and record, or,
/// unranked without enough matchups, its matchups out of [minMatchups].
class _ArenaTile extends StatelessWidget {
  const _ArenaTile({required this.entry, this.minMatchups});

  final ArenaRanked entry;

  /// The matchups it needed to be ranked; given for an unranked one.
  final int? minMatchups;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                entry.qualified ? '${entry.place}' : '–',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 44, child: CardboardCard(child: SketchView(card.sketch))),
            const SizedBox(width: 8),
            Expanded(
              child: Nameplate(name: card.subject, title: card.title, compact: true),
            ),
            const SizedBox(width: 12),
            Text(
              entry.qualified ? entry.record : '${entry.matchups} of ${minMatchups ?? Arena.minMatchups} matchups',
              style: textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The boost balance a week's fights gave the week after: the boost stars
/// to give a day, and how they changed with the heroes' win rate. The rules
/// behind it are in the boost tutorial.
class BoostBalanceCard extends StatelessWidget {
  const BoostBalanceCard({super.key, required this.balance});

  final BoostBalance balance;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final b = balance;
    final change = switch (b.change) {
      > 0 => 'Up from ${b.previousStars} ★ from last week',
      < 0 => 'Down from ${b.previousStars} ★ from last week',
      _ => 'Same as last week',
    };
    final why = b.counted ? 'hero win rate ${b.heroPercent}%' : 'only ${b.fights} fights';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.balance_rounded, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Boost balance', style: textTheme.titleMedium)),
                Text('${b.stars} ★ a day', style: textTheme.titleMedium?.copyWith(color: AppPalette.rarityHero)),
              ],
            ),
            const SizedBox(height: 4),
            Text('$change ($why)', style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

void _openDetails(BuildContext context, RankedChallenger entry, DailyTheme dayTheme) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => RankingDetailScreen(entry: entry, dayTheme: dayTheme)));

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

/// A weekly hero, before and bigger than the other challengers: its drawing
/// large, its place, its nameplate and its stars, framed in the colour of
/// the rarity it was crowned with.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.entry, required this.dayTheme});

  final RankedChallenger entry;

  /// The theme of the day it was drawn, for its details.
  final DailyTheme dayTheme;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final text = Theme.of(context).textTheme;
    final rarity = entry.heroRarity!;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: rarity.color, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetails(context, entry, dayTheme),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events_rounded, color: rarity.color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '#${entry.place} · Weekly hero · ${'★' * rarity.stars}',
                      style: text.titleMedium?.copyWith(color: rarity.color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(width: 160, child: CardboardCard(child: SketchView(card.sketch))),
              const SizedBox(height: 12),
              Nameplate(name: card.subject, title: card.title, rarity: card.rarity),
              const SizedBox(height: 8),
              Text('${entry.stars} ★', style: text.headlineSmall?.copyWith(color: rarity.color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({required this.entry, required this.dayTheme});

  final RankedChallenger entry;

  /// The theme of the day it was drawn, for its details.
  final DailyTheme dayTheme;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetails(context, entry, dayTheme),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text('${entry.place}', style: textTheme.titleMedium, textAlign: TextAlign.center),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 44, child: CardboardCard(child: SketchView(card.sketch))),
              const SizedBox(width: 8),
              Expanded(
                child: Nameplate(name: card.subject, title: card.title, rarity: card.rarity, compact: true),
              ),
              const SizedBox(width: 12),
              Text('${entry.stars} ★', style: textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
