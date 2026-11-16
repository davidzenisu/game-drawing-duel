import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/sketch_canvas.dart';
import 'ranking_detail_screen.dart';

/// The latest finished week's challengers, most stars first: the first
/// joined the gacha pool as a hero. Tapping one opens its details.
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  WeekRanking? _ranking;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// The ranking kept on the device, or asked again with [refresh].
  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    final ranking = await runGameQuery(context, () => widget.controller.weekRanking(refresh: refresh));
    if (!mounted) return;
    setState(() {
      _ranking = ranking ?? (refresh ? _ranking : null);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ranking = _ranking;
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
      body: _loading && ranking == null
          ? const Center(child: CircularProgressIndicator())
          : ranking == null || ranking.challengers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No ranking yet. Once a week is over, its challengers are ranked by their stars.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'The week up to day ${ranking.day}: ${ranking.challengers.length} challengers, ranked by '
                          'their own ${Stars.challengerBase} ★ plus their boost stars.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        PlayersDashboard(players: widget.controller.server.players, ranking: ranking),
                        const SizedBox(height: 12),
                        _WinnerCard(entry: ranking.challengers.first),
                        const SizedBox(height: 8),
                        for (final (i, entry) in ranking.challengers.indexed.skip(1))
                          _RankTile(place: i + 1, entry: entry),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

void _openDetails(BuildContext context, int place, RankedChallenger entry) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => RankingDetailScreen(place: place, entry: entry),
  ),
);

/// How a player did in a week's ranking: the challengers portraying them,
/// the ones they drew, and the best place of either.
class PlayerWeek {
  const PlayerWeek({required this.name, required this.portrayed, required this.drew, this.bestPlace});

  final String name;
  final int portrayed;
  final int drew;
  final int? bestPlace;

  /// Every player of the roster, most portrayed first.
  static List<PlayerWeek> of(List<Player> players, WeekRanking ranking) {
    final entries = [
      for (final player in players)
        PlayerWeek(
          name: player.name,
          portrayed: ranking.challengers.where((c) => c.card.subject == player.name).length,
          drew: ranking.challengers.where((c) => c.card.artist == player.name).length,
          bestPlace: switch (ranking.challengers.indexWhere(
            (c) => c.card.subject == player.name || c.card.artist == player.name,
          )) {
            -1 => null,
            final index => index + 1,
          },
        ),
    ];
    return entries..sort((a, b) {
      final byPortrayed = b.portrayed.compareTo(a.portrayed);
      return byPortrayed != 0 ? byPortrayed : a.name.compareTo(b.name);
    });
  }
}

/// The week at a glance: how often each player was portrayed by the
/// challengers, as a bar, with how many they drew and their best place.
class PlayersDashboard extends StatelessWidget {
  const PlayersDashboard({super.key, required this.players, required this.ranking});

  final List<Player> players;
  final WeekRanking ranking;

  @override
  Widget build(BuildContext context) {
    final weeks = PlayerWeek.of(players, ranking);
    final most = weeks.fold(1, (most, w) => w.portrayed > most ? w.portrayed : most);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("This week's players", style: text.titleMedium),
            Text('Challengers portraying each player', style: text.bodySmall),
            const SizedBox(height: 8),
            for (final week in weeks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Tooltip(
                  message:
                      '${week.name}: portrayed ${week.portrayed}×, drew ${week.drew}'
                      '${week.bestPlace == null ? '' : ', best place #${week.bestPlace}'}',
                  child: Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(week.name, style: text.labelLarge, overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              height: 12,
                              width: week.portrayed == 0 ? 2 : constraints.maxWidth * week.portrayed / most,
                              decoration: BoxDecoration(
                                color: week.portrayed == 0
                                    ? theme.colorScheme.outlineVariant
                                    : theme.colorScheme.primary,
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 112,
                        child: Text(
                          '${week.portrayed} · drew ${week.drew}${week.bestPlace == null ? '' : ' · #${week.bestPlace}'}',
                          style: text.bodySmall,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
