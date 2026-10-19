import 'dart:math';

import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';

/// How long a pull builds up before it flips: the rarer, the longer.
Duration _buildUpFor(Rarity rarity) => Duration(milliseconds: 800 + 400 * rarity.index);

/// The build-up's colour at [t]: it climbs through the rarities' colours up
/// to [rarity]'s, so the rarer the pull, the further it climbs.
Color _climb(double t, Rarity rarity) {
  final steps = rarity.index;
  if (steps == 0) return Color.lerp(Colors.white, rarity.color, t)!;
  final position = t * steps;
  final step = min(position.floor(), steps - 1);
  return Color.lerp(
    Rarity.values[step].color,
    Rarity.values[step + 1].color,
    Curves.easeIn.transform((position - step).clamp(0.0, 1.0)),
  )!;
}

bool _isRare(PullOutcome outcome) => outcome.card.rarity.stars >= Rarity.hero.stars;

/// Full screen reveal of pulls. A single pull builds up, flips and bursts.
/// A multi-pull builds up to its best pull, deals the cards out face down
/// and flips them one after another, then spotlights each 3 and 4 star
/// character before the results.
class PullRevealScreen extends StatefulWidget {
  const PullRevealScreen({super.key, required this.outcomes});

  final List<PullOutcome> outcomes;

  @override
  State<PullRevealScreen> createState() => _PullRevealScreenState();
}

class _PullRevealScreenState extends State<PullRevealScreen> {
  final _spotlights = <PullOutcome>[];
  PullOutcome? _spotlight;

  bool get _single => widget.outcomes.length == 1;

  void _revealed({required bool skipped}) {
    if (skipped) return;
    _spotlights.addAll(widget.outcomes.where(_isRare));
    _nextSpotlight();
  }

  void _nextSpotlight() => setState(() => _spotlight = _spotlights.isEmpty ? null : _spotlights.removeAt(0));

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final spotlight = _single ? widget.outcomes.single : _spotlight;
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.96),
      body: SafeArea(
        child: Stack(
          children: [
            if (!_single)
              Positioned.fill(
                child: _MultiPull(
                  outcomes: widget.outcomes,
                  onRevealed: _revealed,
                  onInspect: (outcome) => setState(() => _spotlight = outcome),
                  onDone: _close,
                ),
              ),
            if (spotlight != null)
              Positioned.fill(
                child: _SingleReveal(
                  key: ObjectKey(spotlight),
                  outcome: spotlight,
                  // A multi-pull's cards are already face up.
                  buildUp: _single,
                  onDone: _single ? _close : _nextSpotlight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One character: the card back builds up, shaking harder and climbing
/// through the rarities' colours, flips and bursts; legends flash. Its
/// stars pop in one by one. Tap to see it all, then to move on.
class _SingleReveal extends StatefulWidget {
  const _SingleReveal({super.key, required this.outcome, required this.buildUp, required this.onDone});

  final PullOutcome outcome;
  final bool buildUp;
  final VoidCallback onDone;

  @override
  State<_SingleReveal> createState() => _SingleRevealState();
}

class _SingleRevealState extends State<_SingleReveal> with TickerProviderStateMixin {
  late final _rarity = widget.outcome.card.rarity;
  late final _charge = AnimationController(vsync: this, duration: _buildUpFor(_rarity));
  late final _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void initState() {
    super.initState();
    _charge.addStatusListener((status) {
      if (status == AnimationStatus.completed && _flip.isDismissed) _flip.forward();
    });
    _flip.addStatusListener((status) {
      if (status == AnimationStatus.completed && _burst.isDismissed) _burst.forward();
    });
    if (widget.buildUp) {
      _charge.forward();
    } else {
      _charge.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _showAll();
  }

  void _showAll() {
    _charge.value = 1;
    _flip.value = 1;
    _burst.value = 1;
  }

  void _tap() {
    if (_burst.isCompleted) {
      widget.onDone();
    } else {
      _showAll();
    }
  }

  @override
  void dispose() {
    _charge.dispose();
    _flip.dispose();
    _burst.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rarity = _rarity;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_charge, _flip, _burst, _spin]),
        builder: (context, _) {
          final charge = _charge.value;
          final burst = _burst.value;
          final color = _flip.value < 0.5 ? _climb(charge, rarity) : rarity.color;
          // Legends burst out of a white flash.
          final flash = rarity == Rarity.legend && burst > 0
              ? 0.9 * (1 - const Interval(0, 0.35).transform(burst))
              : 0.0;
          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.96))),
              Positioned.fill(
                child: CustomPaint(
                  painter: _RaysPainter(
                    color: color,
                    intensity: charge * 0.5 + burst * 0.5,
                    rotation: _spin.value * 2 * pi,
                    rayCount: 6 + rarity.stars * 4,
                    burst: Curves.easeOut.transform(const Interval(0, 0.6).transform(burst)),
                    sparkle: rarity.stars >= Rarity.hero.stars,
                  ),
                ),
              ),
              Center(child: _card(context, color)),
              if (flash > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Colors.white.withValues(alpha: flash)),
                  ),
                ),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: _burst.isCompleted ? 1 : 0.4,
                  child: Text(
                    _burst.isCompleted ? 'Tap to continue' : 'Tap to skip',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, Color glow) {
    final charge = _charge.value;
    // The card shakes harder the further the build-up climbs.
    final shake = _flip.value == 0 ? sin(charge * pi * 18) * charge * (1 + _rarity.index * 2.5) : 0.0;
    final angle = Curves.easeInOut.transform(_flip.value) * pi;
    final showFront = angle > pi / 2;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..translateByDouble(shake, 0, 0, 1)
        ..rotateY(showFront ? angle - pi : angle)
        ..scaleByDouble(1 + 0.06 * charge * (1 - _flip.value), 1 + 0.06 * charge * (1 - _flip.value), 1, 1),
      child: showFront ? _front(context) : CardBack(width: 200, glow: glow.withValues(alpha: charge)),
    );
  }

  Widget _front(BuildContext context) {
    final outcome = widget.outcome;
    final card = outcome.card;
    final burst = _burst.value;
    final details = const Interval(0.6, 0.85).transform(burst);
    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: 1 + 0.08 * Curves.elasticOut.transform(burst),
            child: Standee(card: card, width: 200),
          ),
          const SizedBox(height: 12),
          _PoppingStars(rarity: card.rarity, progress: const Interval(0.15, 0.7).transform(burst)),
          const SizedBox(height: 8),
          Nameplate(name: card.subject, title: card.title),
          const SizedBox(height: 12),
          Opacity(
            opacity: details,
            child: Column(
              children: [
                Chip(
                  backgroundColor: outcome.isNew ? card.rarity.color : null,
                  avatar: Icon(outcome.isNew ? Icons.fiber_new_rounded : Icons.upgrade_rounded),
                  label: Text(outcome.isNew ? 'New character!' : 'Duplicate · +1 upgrade point (×${outcome.copies})'),
                ),
                Text('drawn by ${card.artist}', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A rarity's stars, popping in one after another as [progress] runs.
class _PoppingStars extends StatelessWidget {
  const _PoppingStars({required this.rarity, required this.progress});

  final Rarity rarity;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final count = rarity.stars;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Transform.scale(
            scale: Interval(i / count * 0.7, i / count * 0.7 + 0.3, curve: Curves.easeOutBack).transform(progress),
            child: Icon(
              Icons.star_rounded,
              size: 36,
              color: rarity.color,
              shadows: [Shadow(color: rarity.color, blurRadius: 12)],
            ),
          ),
      ],
    );
  }
}

/// Several pulls: they build up as a stack to the best one's rarity, are
/// dealt out face down, glowing in their rarity's colour, and flip one
/// after another. Tap to hurry each step along.
class _MultiPull extends StatefulWidget {
  const _MultiPull({required this.outcomes, required this.onRevealed, required this.onInspect, required this.onDone});

  final List<PullOutcome> outcomes;

  /// Every card is face up; [skipped] when the player skipped there.
  final void Function({required bool skipped}) onRevealed;
  final ValueChanged<PullOutcome> onInspect;
  final VoidCallback onDone;

  @override
  State<_MultiPull> createState() => _MultiPullState();
}

class _MultiPullState extends State<_MultiPull> with TickerProviderStateMixin {
  late final _best = widget.outcomes
      .map((outcome) => outcome.card.rarity)
      .reduce((best, rarity) => rarity.index > best.index ? rarity : best);
  late final _charge = AnimationController(vsync: this, duration: _buildUpFor(_best));
  late final _deal = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  late final _cascade = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 260 * widget.outcomes.length + 400),
  );
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _charge.addStatusListener((status) {
      if (status == AnimationStatus.completed && _deal.isDismissed) _deal.forward();
    });
    _deal.addStatusListener((status) {
      if (status == AnimationStatus.completed && _cascade.isDismissed) _cascade.forward();
    });
    _cascade.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish(skipped: false);
    });
    _charge.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish(skipped: true);
      });
    }
  }

  void _finish({required bool skipped}) {
    if (_revealed) return;
    setState(() => _revealed = true);
    _charge.value = 1;
    _deal.value = 1;
    _cascade.value = 1;
    widget.onRevealed(skipped: skipped);
  }

  /// Hurries the current step along.
  void _tap() {
    if (_charge.isAnimating) {
      _charge.value = 1;
    } else if (_deal.isAnimating) {
      _deal.value = 1;
    } else if (_cascade.isAnimating) {
      _finish(skipped: false);
    }
  }

  @override
  void dispose() {
    _charge.dispose();
    _deal.dispose();
    _cascade.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Text(
                _revealed ? 'Your pulls' : '${widget.outcomes.length} pulls',
                style: textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const Spacer(),
              if (!_revealed)
                TextButton(
                  onPressed: () => _finish(skipped: true),
                  child: const Text('Skip', style: TextStyle(color: Colors.white)),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tap,
            child: AnimatedBuilder(
              animation: Listenable.merge([_charge, _deal, _cascade, _spin]),
              builder: (context, _) => Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RaysPainter(
                        color: _climb(_charge.value, _best),
                        // The light fades as the cards are dealt out.
                        intensity: _charge.value * (1 - 0.7 * _deal.value),
                        rotation: _spin.value * 2 * pi,
                        rayCount: 6 + _best.stars * 4,
                        burst: 0,
                        sparkle: false,
                      ),
                    ),
                  ),
                  if (_deal.isDismissed) Center(child: _stack()) else Positioned.fill(child: _grid()),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _revealed
              ? FilledButton(onPressed: widget.onDone, child: const Text('Done'))
              : Text('Tap to hurry', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ),
      ],
    );
  }

  /// The face down stack, shaking and glowing as it builds up.
  Widget _stack() {
    final charge = _charge.value;
    final glow = _climb(charge, _best).withValues(alpha: charge);
    final shake = sin(charge * pi * 18) * charge * (1 + _best.index * 2.5);
    return Transform.translate(
      offset: Offset(shake, 0),
      child: SizedBox(
        width: 180,
        height: 210,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 2; i >= 0; i--)
              Transform.translate(
                offset: Offset(i * 6.0, i * -6.0),
                child: CardBack(width: 150, glow: i == 0 ? glow : null),
              ),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    final outcomes = widget.outcomes;
    final count = outcomes.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        const labels = 52.0;
        final columns = min(count, 5);
        final rows = (count / columns).ceil();
        final width = min(
          min(104.0, (constraints.maxWidth - 32 - (columns - 1) * gap) / columns),
          // Standees are a little taller than wide, plus their labels.
          ((constraints.maxHeight - 16 - (rows - 1) * gap) / rows - labels) / 1.45,
        );
        // Each card is dealt a moment after the one before, then flips the
        // same way.
        final dealStep = 0.6 / count;
        final flipStep = 0.85 / count;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (i, outcome) in outcomes.indexed)
                  _tile(
                    outcome,
                    width: width,
                    dealt: Interval(
                      i * dealStep,
                      i * dealStep + 0.4,
                      curve: Curves.easeOutCubic,
                    ).transform(_deal.value),
                    flipped: Interval(
                      i * flipStep,
                      i * flipStep + 0.15,
                      curve: Curves.easeInOut,
                    ).transform(_cascade.value),
                    side: i.isEven ? 1 : -1,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tile(
    PullOutcome outcome, {
    required double width,
    required double dealt,
    required double flipped,
    required int side,
  }) {
    final card = outcome.card;
    final rarity = card.rarity;
    final angle = flipped * pi;
    final showFront = angle > pi / 2;
    // Rare cards ring out as they turn face up.
    final ring = _isRare(outcome) && showFront ? (flipped - 0.5) * 2 : 0.0;
    return GestureDetector(
      onTap: _revealed ? () => widget.onInspect(outcome) : null,
      child: Opacity(
        opacity: dealt > 0 ? 1 : 0,
        child: Transform.translate(
          offset: Offset(0, (1 - dealt) * 320),
          child: Transform.rotate(
            angle: (1 - dealt) * 0.6 * side,
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    foregroundPainter: ring > 0 && ring < 1 ? _RingPainter(color: rarity.color, progress: ring) : null,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..rotateY(showFront ? angle - pi : angle),
                      child: showFront
                          ? Standee(card: card, width: width)
                          // Face down in a base too, so nothing moves as it
                          // flips; the back glows in the rarity's colour.
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CardBack(
                                  width: width,
                                  glow: rarity.color.withValues(alpha: 0.8 * dealt),
                                ),
                                StandeeBase(width: width * 0.62),
                              ],
                            ),
                    ),
                  ),
                  Opacity(
                    opacity: showFront ? 1 : 0,
                    child: Column(
                      children: [
                        StarRow(rarity: rarity, size: 14),
                        Text(
                          card.subject,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          outcome.isNew ? 'NEW' : '+1 upgrade',
                          style: TextStyle(color: outcome.isNew ? rarity.color : Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring spreading out from a card that turns face up.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      size.longestSide * (0.4 + 0.5 * progress),
      Paint()
        ..color = color.withValues(alpha: 1 - progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * (1 - progress),
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}

class _RaysPainter extends CustomPainter {
  _RaysPainter({
    required this.color,
    required this.intensity,
    required this.rotation,
    required this.rayCount,
    required this.burst,
    required this.sparkle,
  });

  final Color color;
  final double intensity;
  final double rotation;
  final int rayCount;
  final double burst;
  final bool sparkle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.longestSide;
    canvas.drawCircle(
      center,
      size.shortestSide * (0.2 + 0.25 * intensity),
      Paint()
        ..color = color.withValues(alpha: 0.6 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );
    final ray = Paint()..color = color.withValues(alpha: 0.18 * intensity);
    for (var i = 0; i < rayCount; i++) {
      final a = rotation + i * 2 * pi / rayCount;
      final spread = pi / rayCount * 0.45;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + cos(a - spread) * radius, center.dy + sin(a - spread) * radius)
        ..lineTo(center.dx + cos(a + spread) * radius, center.dy + sin(a + spread) * radius)
        ..close();
      canvas.drawPath(path, ray);
    }
    if (burst > 0 && burst < 1) {
      canvas.drawCircle(
        center,
        size.shortestSide * 0.6 * burst,
        Paint()
          ..color = color.withValues(alpha: 1 - burst)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * (1 - burst),
      );
      if (sparkle) {
        final random = Random(7);
        final dot = Paint()..color = Colors.white.withValues(alpha: 1 - burst);
        for (var i = 0; i < 40; i++) {
          final a = random.nextDouble() * 2 * pi;
          final d = size.shortestSide * (0.15 + random.nextDouble() * 0.5) * burst;
          canvas.drawCircle(center + Offset(cos(a), sin(a)) * d, 2 + random.nextDouble() * 3, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RaysPainter oldDelegate) => true;
}
