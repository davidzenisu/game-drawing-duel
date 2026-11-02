import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../widgets/game_action.dart';

/// This week's win rates, from last week's fights: how each player's
/// characters did against each other player's, and the extra stars that
/// gives them this week.
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

  @override
  Widget build(BuildContext context) {
    final rates = _rates;
    final textTheme = Theme.of(context).textTheme;
    // Most extra stars first, then the most meetings.
    final rows = [...?rates?.rates]
      ..sort((a, b) {
        final byStars = b.extraStars.compareTo(a.extraStars);
        if (byStars != 0) return byStars;
        final byFights = b.fights.compareTo(a.fights);
        return byFights != 0 ? byFights : a.player.name.compareTo(b.player.name);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Win rates')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                          'Characters count for the player they show, and every fighter meets the challenger once. '
                          'Win more than half of at least ${WinRates.minFights} meetings against a player last week '
                          'for +1 ★ against them this week, more than three quarters for +2 ★.',
                          style: textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        if (rates == null || rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              rates == null
                                  ? 'Speed mode has no win rates.'
                                  : 'No win rates this week: nobody fought last week.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        else ...[
                          Text(
                            'From the fights of days ${rates.fromDay} to ${rates.toDay}',
                            style: textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          _WinRateTable(rows: rows),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _WinRateTable extends StatelessWidget {
  const _WinRateTable({required this.rows});

  final List<WinRate> rows;

  static String _name(Player player) => player.isYou ? '${player.name} (you)' : player.name;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final header = textTheme.labelLarge;
    Widget cell(String text, {TextStyle? style, TextAlign align = TextAlign.start}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Text(text, style: style, textAlign: align),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(2),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              children: [
                cell('Player', style: header),
                cell('Against', style: header),
                cell('Won', style: header, align: TextAlign.end),
                cell('Extra', style: header, align: TextAlign.end),
              ],
            ),
            for (final rate in rows)
              TableRow(
                children: [
                  cell(_name(rate.player)),
                  cell(_name(rate.against)),
                  cell('${rate.wins} / ${rate.fights}', align: TextAlign.end),
                  cell(
                    rate.extraStars == 0 ? '–' : '+${rate.extraStars} ★',
                    align: TextAlign.end,
                    style: rate.extraStars == 0
                        ? null
                        : textTheme.titleSmall?.copyWith(color: AppPalette.rarityLegend, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
