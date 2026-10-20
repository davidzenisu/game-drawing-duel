import 'dart:async';
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

/// Full screen reveal of pulls. A single pull builds up, flips and bursts.
/// A multi-pull spins its cards into a carousel face down, every back
/// glowing in its rarity's colour, then reveals them one by one the same
/// way, and ends on an overview of them all.
class PullRevealScreen extends StatefulWidget {
  const PullRevealScreen({super.key, required this.outcomes});

  final List<PullOutcome> outcomes;

  @override
  State<PullRevealScreen> createState() => _PullRevealScreenState();
}

class _PullRevealScreenState extends State<PullRevealScreen> {
  PullOutcome? _spotlight;

  /// While a multi-pull reveals its cards one by one: how far it got, and
  /// what comes after this card or after skipping the rest.
  String? _progress;
  VoidCallback? _next;
  VoidCallback? _skip;

  bool get _single => widget.outcomes.length == 1;

  void _reveal(PullOutcome outcome, String progress, VoidCallback next, VoidCallback skip) => setState(() {
    _spotlight = outcome;
    _progress = progress;
    _next = next;
    _skip = skip;
  });

  /// Shows a card again from the overview.
  void _inspect(PullOutcome outcome) => setState(() {
    _spotlight = outcome;
    _progress = _next = _skip = null;
  });

  /// Hides the spotlight, then calls [then].
  void _leave(VoidCallback? then) {
    setState(() {
      _spotlight = null;
      _progress = _next = _skip = null;
    });
    then?.call();
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final spotlight = _single ? widget.outcomes.single : _spotlight;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (!_single)
              Positioned.fill(
                child: _MultiPull(outcomes: widget.outcomes, onReveal: _reveal, onInspect: _inspect, onDone: _close),
              ),
            if (spotlight != null)
              Positioned.fill(
                child: _SingleReveal(
                  key: ObjectKey(spotlight),
                  outcome: spotlight,
                  // Cards shown again from the overview are face up already.
                  buildUp: _single || _next != null,
                  progress: _progress,
                  onSkip: _skip == null ? null : () => _leave(_skip),
                  onDone: _single ? _close : () => _leave(_next),
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
  const _SingleReveal({
    super.key,
    required this.outcome,
    required this.buildUp,
    required this.onDone,
    this.progress,
    this.onSkip,
  });

  final PullOutcome outcome;
  final bool buildUp;
  final VoidCallback onDone;

  /// Which of several pulls this is, e.g. "3 / 10".
  final String? progress;

  /// Skips the rest of several pulls.
  final VoidCallback? onSkip;

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
              // Opaque, so nothing of a multi-pull underneath shows through.
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
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
              if (widget.progress != null || widget.onSkip != null)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 8,
                  child: Row(
                    children: [
                      Text(
                        widget.progress ?? '',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (widget.onSkip != null)
                        TextButton(
                          onPressed: widget.onSkip,
                          child: const Text('Skip', style: TextStyle(color: Colors.white)),
                        ),
                    ],
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

enum _Stage { carousel, reveal, results }

/// Several pulls. They spin into a carousel face down, every back lighting
/// up in its rarity's colour at once, then each one gets a reveal of its
/// own in order, and the overview of them all comes last.
class _MultiPull extends StatefulWidget {
  const _MultiPull({required this.outcomes, required this.onReveal, required this.onInspect, required this.onDone});

  final List<PullOutcome> outcomes;

  /// Reveals one card, then calls `next`; `skip` skips the rest.
  final void Function(PullOutcome outcome, String progress, VoidCallback next, VoidCallback skip) onReveal;
  final ValueChanged<PullOutcome> onInspect;
  final VoidCallback onDone;

  @override
  State<_MultiPull> createState() => _MultiPullState();
}

class _MultiPullState extends State<_MultiPull> with TickerProviderStateMixin {
  /// The cards spread out and turn once round while their backs light up.
  late final _carousel = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  var _stage = _Stage.carousel;
  Timer? _pause;

  @override
  void initState() {
    super.initState();
    _carousel.addStatusListener((status) {
      // A moment to take in the colours before the reveals.
      if (status == AnimationStatus.completed) _pause = Timer(const Duration(milliseconds: 900), _startReveals);
    });
    _carousel.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toResults();
      });
    }
  }

  void _startReveals() {
    if (!mounted || _stage != _Stage.carousel) return;
    _pause?.cancel();
    setState(() => _stage = _Stage.reveal);
    _reveal(0);
  }

  void _reveal(int index) {
    if (!mounted || _stage != _Stage.reveal) return;
    final outcomes = widget.outcomes;
    if (index >= outcomes.length) return _toResults();
    widget.onReveal(outcomes[index], '${index + 1} / ${outcomes.length}', () => _reveal(index + 1), _toResults);
  }

  void _toResults() {
    if (!mounted || _stage == _Stage.results) return;
    _pause?.cancel();
    _carousel.stop();
    setState(() => _stage = _Stage.results);
  }

  /// Hurries the carousel along.
  void _tap() {
    if (_carousel.isAnimating) {
      _carousel.value = 1;
    } else {
      _startReveals();
    }
  }

  @override
  void dispose() {
    _pause?.cancel();
    _carousel.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final results = _stage == _Stage.results;
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  results ? 'Your pulls' : '${widget.outcomes.length} pulls',
                  style: textTheme.titleLarge?.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!results)
                TextButton(
                  onPressed: _toResults,
                  child: const Text('Skip', style: TextStyle(color: Colors.white)),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        Expanded(
          child: results
              ? _results()
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _tap,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_carousel, _spin]),
                    builder: (context, _) => _ring(),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: results
              ? FilledButton(onPressed: widget.onDone, child: const Text('Done'))
              : Text('Tap to hurry', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ),
      ],
    );
  }

  Widget _ring() {
    final outcomes = widget.outcomes;
    final count = outcomes.length;
    final t = _carousel.value;
    final spread = const Interval(0, 0.35, curve: Curves.easeOutBack).transform(t);
    // One turn round, slowing down until the first card is at the front.
    final position = -count * (1 - Curves.easeOutCubic.transform(t));
    // All backs light up together, then pulse gently.
    final glow = const Interval(0.3, 0.7, curve: Curves.easeIn).transform(t);
    final pulse = 0.85 + 0.15 * sin(_spin.value * 2 * pi * 6);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(140.0, min(constraints.maxWidth * 0.34, constraints.maxHeight * 0.5 / 1.45));
        final radius = width * 1.6 * spread;
        double angle(int i) => 2 * pi * (i - position) / count;
        // Back cards first, so the front one is drawn on top.
        final order = [for (var i = 0; i < count; i++) i]..sort((a, b) => cos(angle(a)).compareTo(cos(angle(b))));
        // Just the dark background, so the glows stand out.
        return Stack(
          alignment: Alignment.center,
          children: [
            for (final i in order)
              _ringCard(outcomes[i], width: width, angle: angle(i), radius: radius, glow: glow * pulse),
          ],
        );
      },
    );
  }

  Widget _ringCard(
    PullOutcome outcome, {
    required double width,
    required double angle,
    required double radius,
    required double glow,
  }) {
    final facing = cos(angle);
    // Cards at the back fade into the dark, darkened rather than see-through
    // so the ones behind them don't show through.
    return ColorFiltered(
      colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.7 * (1 - facing) / 2), BlendMode.srcATop),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          // Seen from a little above, so the ring's far side rises.
          ..rotateX(0.45)
          ..translateByDouble(sin(angle) * radius, 0, radius * (1 - facing), 1)
          ..rotateY(angle),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Only the glow tells the rarity, never the character.
            CardBack(
              width: width,
              glow: outcome.card.rarity.color.withValues(alpha: glow.clamp(0.0, 1.0)),
            ),
            StandeeBase(width: width * 0.62),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    final outcomes = widget.outcomes;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        const labels = 52.0;
        final count = outcomes.length;
        final columns = min(count, 5);
        final rows = (count / columns).ceil();
        final width = min(
          min(104.0, (constraints.maxWidth - 32 - (columns - 1) * gap) / columns),
          // Standees are a little taller than wide, plus their labels.
          ((constraints.maxHeight - 32 - (rows - 1) * gap) / rows - labels) / 1.45,
        );
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (i, outcome) in outcomes.indexed)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 300 + i * 60),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) => Transform.scale(scale: value, child: child),
                    child: GestureDetector(
                      onTap: () => widget.onInspect(outcome),
                      child: SizedBox(
                        width: width,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Standee(card: outcome.card, width: width),
                            StarRow(rarity: outcome.card.rarity, size: 14),
                            Text(
                              outcome.card.subject,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              outcome.isNew ? 'NEW' : '+1 upgrade',
                              style: TextStyle(
                                color: outcome.isNew ? outcome.card.rarity.color : Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
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
