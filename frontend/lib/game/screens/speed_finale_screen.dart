import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';

/// The end of a speed mode session: the challenger with the most stars is
/// presented first, its stars counting up, then every other challenger
/// scrolls by in a smaller display, with its stars.
class SpeedFinaleScreen extends StatefulWidget {
  const SpeedFinaleScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<SpeedFinaleScreen> createState() => _SpeedFinaleScreenState();
}

class _SpeedFinaleScreenState extends State<SpeedFinaleScreen> {
  /// How long the winner has the stage before the others scroll by.
  static const winnerTime = Duration(milliseconds: 2500);

  /// How long each of the others is in view while scrolling by.
  static const perChallenger = Duration(milliseconds: 1400);

  final _strip = ScrollController();
  WeekRanking? _ranking;
  bool _loading = true;

  /// Scrolling by on its own until the player takes over.
  bool _auto = true;
  Timer? _pause;
  int _others = 0;

  @override
  void initState() {
    super.initState();
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pause?.cancel();
    _strip.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ranking = await runGameQuery(context, widget.controller.weekRanking);
    if (!mounted) return;
    setState(() {
      _ranking = ranking;
      _loading = false;
    });
    _others = (ranking?.challengers.length ?? 1) - 1;
    if (_others > 0) _after(winnerTime, _forward);
  }

  /// Runs [step] after [wait], while still scrolling on its own.
  void _after(Duration wait, VoidCallback step) {
    _pause?.cancel();
    if (!mounted || !_auto) return;
    _pause = Timer(wait, () {
      if (mounted && _auto && _strip.hasClients) step();
    });
  }

  /// Scrolls through the others, then back to the start, over and over.
  void _forward() => _strip
      .animateTo(_strip.position.maxScrollExtent, duration: perChallenger * _others, curve: Curves.linear)
      .then((_) => _after(const Duration(seconds: 2), _back));

  void _back() => _strip
      .animateTo(0, duration: const Duration(milliseconds: 800), curve: Curves.easeInOutCubic)
      .then((_) => _after(const Duration(seconds: 1), _forward));

  @override
  Widget build(BuildContext context) {
    final ranking = _ranking;
    final challengers = ranking?.challengers ?? const <RankedChallenger>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Final ranking')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : challengers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No challengers this time.', textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                Expanded(child: _Winner(entry: challengers.first)),
                if (challengers.length > 1) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('Every challenger', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  SizedBox(
                    height: 190,
                    child: NotificationListener<UserScrollNotification>(
                      // Once the player scrolls themselves, it stays theirs.
                      onNotification: (_) {
                        _auto = false;
                        return false;
                      },
                      child: ListView.separated(
                        controller: _strip,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: challengers.length - 1,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => _Runner(place: i + 2, entry: challengers[i + 1]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// The winner, on stage: its standee pops in and its stars count up.
class _Winner extends StatelessWidget {
  const _Winner({required this.entry});

  final RankedChallenger entry;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('The winner', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.elasticOut,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Standee(card: card, width: 150),
              ),
              const SizedBox(height: 8),
              Text(card.subject, style: textTheme.headlineSmall, textAlign: TextAlign.center),
              Text(card.title, style: textTheme.titleMedium, textAlign: TextAlign.center),
              Text('Drawn by ${card.artist}', style: textTheme.bodySmall),
              const SizedBox(height: 8),
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: entry.stars),
                duration: const Duration(milliseconds: 1600),
                curve: Curves.easeOutCubic,
                builder: (context, stars, _) => Text(
                  '$stars ★',
                  style: textTheme.displaySmall?.copyWith(color: AppPalette.rarityLegend, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the other challengers, smaller, with its place and stars.
class _Runner extends StatelessWidget {
  const _Runner({required this.place, required this.entry});

  final int place;
  final RankedChallenger entry;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 120,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Text('#$place', style: textTheme.labelLarge),
              Expanded(
                child: FittedBox(child: Standee(card: card, width: 70)),
              ),
              Text(card.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.labelLarge),
              Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
              Text('${entry.stars} ★', style: textTheme.titleSmall?.copyWith(color: AppPalette.rarityLegend)),
            ],
          ),
        ),
      ),
    );
  }
}
