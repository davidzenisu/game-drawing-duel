import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/daily_loop.dart';
import '../widgets/animated_fight.dart';

/// Plays out a fight that ends with the outcome the stars decided.
class FightReplayScreen extends StatefulWidget {
  const FightReplayScreen({super.key, required this.fight, this.rewardPulls});

  final FightSetup fight;

  /// The pulls a win earned you, shown right after you locked in your
  /// fighters; null for replays.
  final int? rewardPulls;

  @override
  State<FightReplayScreen> createState() => _FightReplayScreenState();
}

class _FightReplayScreenState extends State<FightReplayScreen> {
  late final List<FightBeat> _beats = FightScript.build(
    fighterCount: widget.fight.fighters.length,
    fightersWin: widget.fight.fightersWin,
    random: Random(widget.fight.id.hashCode),
  );
  bool _skip = false;
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('The fight'),
        actions: [if (!_finished) TextButton(onPressed: () => setState(() => _skip = true), child: const Text('Skip'))],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedFight(
              fight: widget.fight,
              beats: _beats,
              skip: _skip,
              onFinished: () => setState(() => _finished = true),
            ),
          ),
          if (_finished)
            Positioned.fill(
              child: FightOutcome(fight: widget.fight, rewardPulls: widget.rewardPulls),
            ),
        ],
      ),
    );
  }
}

/// Reveals how a fight ended: each side's stars count up, the side with
/// more stands out and the winner drops in. Tap to see it all at once.
class FightOutcome extends StatefulWidget {
  const FightOutcome({super.key, required this.fight, this.rewardPulls});

  final FightSetup fight;

  /// The pulls a win earned you, shown with the challenger's stars; null
  /// shows no reward.
  final int? rewardPulls;

  @override
  State<FightOutcome> createState() => _FightOutcomeState();
}

class _FightOutcomeState extends State<FightOutcome> with SingleTickerProviderStateMixin {
  late final _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));

  @override
  void initState() {
    super.initState();
    _reveal.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _reveal.value = 1;
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fight = widget.fight;
    final fightersWin = fight.fightersWin;
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _reveal.value = 1,
      child: AnimatedBuilder(
        animation: _reveal,
        builder: (context, _) {
          final t = _reveal.value;
          final appear = const Interval(0, 0.12, curve: Curves.easeOut).transform(t);
          // The fighters' stars count up, then the challenger's, then the
          // side with more stands out and the winner drops in.
          final fighterCount = const Interval(0.1, 0.38, curve: Curves.easeOut).transform(t);
          final challengerCount = const Interval(0.4, 0.68, curve: Curves.easeOut).transform(t);
          final standOut = const Interval(0.7, 0.82, curve: Curves.easeOutBack).transform(t);
          final verdict = const Interval(0.74, 1, curve: Curves.elasticOut).transform(t);
          return ColoredBox(
            color: Colors.black.withValues(alpha: 0.5 * appear),
            child: Center(
              child: Opacity(
                opacity: appear,
                child: Transform.scale(
                  scale: 0.85 + 0.15 * appear,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Card(
                      margin: const EdgeInsets.all(16),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _StarTally(
                                    label: 'Fighters',
                                    stars: (fight.fighterStars * fighterCount).round(),
                                    detail: '${fight.fighters.length} fighter${fight.fighters.length == 1 ? '' : 's'}',
                                    wins: fightersWin,
                                    standOut: standOut,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 28),
                                  child: Text('vs', style: text.titleMedium),
                                ),
                                Expanded(
                                  child: _StarTally(
                                    label: fight.challenger.subject,
                                    stars: (fight.challengerStars * challengerCount).round(),
                                    detail: fight.boostStars == 0
                                        ? 'No boosts'
                                        : '${Stars.challengerBase} + ${fight.boostStars} from boosts',
                                    wins: !fightersWin,
                                    standOut: standOut,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Opacity(
                              opacity: const Interval(0.74, 0.8).transform(t),
                              child: Transform.translate(
                                offset: Offset(0, (1 - verdict) * -24),
                                child: Column(
                                  children: [
                                    const Icon(Icons.emoji_events_rounded, size: 56, color: AppPalette.rarityLegend),
                                    Text(
                                      fightersWin ? 'The fighters win!' : '${fight.challenger.subject} wins!',
                                      textAlign: TextAlign.center,
                                      style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                    if (fight.fighterStars == fight.challengerStars)
                                      const Text('Ties go to the challenger.'),
                                    if (widget.rewardPulls case final pulls? when fightersWin) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '+$pulls pull${pulls == 1 ? '' : 's'} · +${fight.challengerStars} victory ★',
                                        style: text.titleMedium?.copyWith(color: AppPalette.ticket),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One side's stars, counting up; the winning side grows and turns green
/// once [standOut] runs, the other fades.
class _StarTally extends StatelessWidget {
  const _StarTally({
    required this.label,
    required this.stars,
    required this.detail,
    required this.wins,
    required this.standOut,
  });

  final String label;
  final int stars;
  final String detail;
  final bool wins;
  final double standOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Opacity(
      opacity: wins ? 1 : 1 - 0.45 * standOut.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: wins ? 1 + 0.15 * standOut : 1,
        child: Column(
          children: [
            Text(label, style: text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '$stars ★',
              style: text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: wins
                    ? Color.lerp(text.headlineMedium?.color, AppPalette.victory, standOut.clamp(0.0, 1.0))
                    : null,
              ),
            ),
            Text(detail, style: text.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
