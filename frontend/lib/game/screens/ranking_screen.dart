import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
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

  Future<void> _load() async {
    final ranking = await runGameQuery(context, widget.controller.weekRanking);
    if (!mounted) return;
    setState(() {
      _ranking = ranking;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ranking = _ranking;
    return Scaffold(
      appBar: AppBar(title: const Text('Week ranking')),
      body: _loading
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
                        const SizedBox(height: 8),
                        for (final (i, entry) in ranking.challengers.indexed) _RankTile(place: i + 1, entry: entry),
                      ],
                    ),
                  ),
                ),
              ],
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
