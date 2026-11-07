import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/sketch_canvas.dart';

/// This week's win rates, from last week's fights: every player as a card,
/// each opening the matchups that give extra stars to them or against them.
class WinRatesScreen extends StatefulWidget {
  const WinRatesScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<WinRatesScreen> createState() => _WinRatesScreenState();
}

class _WinRatesScreenState extends State<WinRatesScreen> {
  WeekWinRates? _rates;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final rates = await runGameQuery(context, widget.controller.winRates);
    if (!mounted) return;
    setState(() {
      _rates = rates;
      _loading = false;
    });
  }

  void _open(Player player) {
    final rates = _rates;
    if (rates == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerWinRatesScreen(controller: widget.controller, player: player, rates: rates),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rates = _rates;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Win rates')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : rates == null
          ? const Center(
              child: Padding(padding: EdgeInsets.all(24), child: Text('Speed mode has no win rates.')),
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      // The first week has no week before it to count.
                      '${rates.fromDay < 1 ? 'No win rates yet: they start once the first week is over.' : 'From the fights of days ${rates.fromDay} to ${rates.toDay}.'} '
                      'Characters count for the player they show. Win more than half of at least '
                      '${WinRates.minFights} fights against a player for +1 ★ against them the next week, more than '
                      'three quarters for +2 ★.',
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 170,
                      mainAxisExtent: 250,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: widget.controller.server.players.length,
                    itemBuilder: (context, i) {
                      final player = widget.controller.server.players[i];
                      return _PlayerCard(
                        player: player,
                        drawing: basicDrawingOf(widget.controller, player),
                        onShow: () => _open(player),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// [player]'s basic drawing, their preview, if it's known.
CharacterCard? basicDrawingOf(GameSession controller, Player player) => [
  ...controller.pool,
  ...controller.collection.map((o) => o.card),
].where((c) => c.rarity == Rarity.basic && c.subject == player.name).firstOrNull;

String _name(Player player) => player.isYou ? '${player.name} (you)' : player.name;

/// A player's basic drawing, or a blank card while there's none.
class _Preview extends StatelessWidget {
  const _Preview({required this.drawing, required this.width});

  final CharacterCard? drawing;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: CardboardCard(
      child: switch (drawing) {
        final card? => SketchView(card.sketch),
        null => const Center(child: Icon(Icons.person_rounded, color: Colors.black26)),
      },
    ),
  );
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.player, required this.drawing, required this.onShow});

  final Player player;
  final CharacterCard? drawing;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onShow,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: Center(child: _Preview(drawing: drawing, width: 110)),
              ),
              const SizedBox(height: 6),
              Text(
                _name(player),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onShow,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Win rates', maxLines: 1, softWrap: false, textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [player]'s matchups this week that change stars on either side: theirs
/// against each other player, side by side.
class PlayerWinRatesScreen extends StatelessWidget {
  const PlayerWinRatesScreen({super.key, required this.controller, required this.player, required this.rates});

  final GameSession controller;
  final Player player;
  final WeekWinRates rates;

  WinRate? _rate(Player of, Player against) =>
      rates.rates.where((r) => r.player.name == of.name && r.against.name == against.name).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final matchups = [
      for (final other in controller.server.players)
        if (other.name != player.name) (other: other, theirs: _rate(player, other), others: _rate(other, player)),
    ].where((m) => (m.theirs?.extraStars ?? 0) > 0 || (m.others?.extraStars ?? 0) > 0).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_name(player))),
      body: matchups.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No extra stars for or against ${player.name} this week.', textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final m in matchups)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _MatchupSide(
                                  player: player,
                                  drawing: basicDrawingOf(controller, player),
                                  rate: m.theirs,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text('vs', style: Theme.of(context).textTheme.titleMedium),
                              ),
                              Expanded(
                                child: _MatchupSide(
                                  player: m.other,
                                  drawing: basicDrawingOf(controller, m.other),
                                  rate: m.others,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// One side of a matchup: the player, their extra stars and their record.
class _MatchupSide extends StatelessWidget {
  const _MatchupSide({required this.player, required this.drawing, required this.rate});

  final Player player;
  final CharacterCard? drawing;
  final WinRate? rate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rate = this.rate;
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            _Preview(drawing: drawing, width: 80),
            const SizedBox(height: 6),
            Text(_name(player), maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleSmall),
            // Both lines keep their room on both sides, so the two cards are
            // the same size and line up whichever side has the extra stars.
            Visibility(
              visible: rate != null && rate.extraStars > 0,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Text(
                '+${rate?.extraStars ?? 0} ★',
                style: textTheme.titleMedium?.copyWith(color: AppPalette.rarityLegend, fontWeight: FontWeight.w900),
              ),
            ),
            Visibility(
              visible: rate != null && rate.wins > 0,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Text('won ${rate?.wins ?? 0}/${rate?.fights ?? 0} fights', style: textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
