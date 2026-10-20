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
/// A multi-pull builds up to its best pull, then turns its cards past in a
/// carousel twice: first showing only each one's rarity, then flipping
/// each one, with a full reveal for every 3 and 4 star character.
class PullRevealScreen extends StatefulWidget {
  const PullRevealScreen({super.key, required this.outcomes});

  final List<PullOutcome> outcomes;

  @override
  State<PullRevealScreen> createState() => _PullRevealScreenState();
}

class _PullRevealScreenState extends State<PullRevealScreen> {
  PullOutcome? _spotlight;
  VoidCallback? _afterSpotlight;

  bool get _single => widget.outcomes.length == 1;

  void _show(PullOutcome outcome, [VoidCallback? then]) => setState(() {
    _spotlight = outcome;
    _afterSpotlight = then;
  });

  void _spotlightDone() {
    final then = _afterSpotlight;
    setState(() {
      _spotlight = null;
      _afterSpotlight = null;
    });
    then?.call();
  }

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
                child: _MultiPull(outcomes: widget.outcomes, onRare: _show, onInspect: _show, onDone: _close),
              ),
            if (spotlight != null)
              Positioned.fill(
                child: _SingleReveal(
                  key: ObjectKey(spotlight),
                  outcome: spotlight,
                  // A multi-pull's cards are already face up.
                  buildUp: _single,
                  onDone: _single ? _close : _spotlightDone,
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

enum _Stage { buildUp, preview, reveal, results }

/// Several pulls. They build up as a stack to the best one's rarity, then
/// spread into a carousel that turns each card to the front twice: the
/// first time it only shows its rarity, the second time it flips. Tap to
/// hurry each card along.
class _MultiPull extends StatefulWidget {
  const _MultiPull({required this.outcomes, required this.onRare, required this.onInspect, required this.onDone});

  final List<PullOutcome> outcomes;

  /// A 3 or 4 star character turned face up; the carousel goes on once
  /// `resume` is called.
  final void Function(PullOutcome outcome, VoidCallback resume) onRare;
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

  /// One card's turn: the carousel brings it to the front, then it shows
  /// its rarity or flips.
  late final _step = AnimationController(vsync: this);
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  var _stage = _Stage.buildUp;

  /// The card at the front.
  int _index = 0;

  static const _turnMs = 350;

  /// How long the front card stays after turning; rarer ones show their
  /// rarity longer.
  int _holdMs(PullOutcome outcome) => _stage == _Stage.preview ? 200 + 250 * outcome.card.rarity.index : 550;

  PullOutcome get _front => widget.outcomes[_index];

  /// The part of a step spent turning.
  double get _turnPart => _turnMs / (_turnMs + _holdMs(_front));

  @override
  void initState() {
    super.initState();
    _charge.addStatusListener((status) {
      if (status == AnimationStatus.completed && _stage == _Stage.buildUp) _startStage(_Stage.preview);
    });
    _step.addStatusListener((status) {
      if (status == AnimationStatus.completed) _stepDone();
    });
    _charge.forward();
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

  void _startStage(_Stage stage) {
    setState(() {
      _stage = stage;
      _index = 0;
    });
    _play();
  }

  void _play() {
    _step.duration = Duration(milliseconds: _turnMs + _holdMs(_front));
    _step.forward(from: 0);
  }

  void _stepDone() {
    if (_stage == _Stage.reveal && _isRare(_front)) {
      widget.onRare(_front, () {
        if (mounted && _stage == _Stage.reveal) _next();
      });
    } else {
      _next();
    }
  }

  void _next() {
    if (_index < widget.outcomes.length - 1) {
      setState(() => _index++);
      _play();
    } else if (_stage == _Stage.preview) {
      _startStage(_Stage.reveal);
    } else {
      _toResults();
    }
  }

  void _toResults() {
    if (_stage == _Stage.results) return;
    _charge.stop();
    _step.stop();
    setState(() => _stage = _Stage.results);
  }

  /// Hurries the current card along.
  void _tap() {
    if (_stage == _Stage.buildUp) {
      _charge.value = 1;
    } else if (_step.isAnimating) {
      _step.value = 1;
    }
  }

  @override
  void dispose() {
    _charge.dispose();
    _step.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final count = widget.outcomes.length;
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
                  switch (_stage) {
                    _Stage.buildUp => '$count pulls',
                    _Stage.preview => 'Rarities · ${_index + 1}/$count',
                    _Stage.reveal => 'Reveal · ${_index + 1}/$count',
                    _Stage.results => 'Your pulls',
                  },
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
                    animation: Listenable.merge([_charge, _step, _spin]),
                    builder: (context, _) => _stage == _Stage.buildUp ? _buildUp() : _carousel(),
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

  Widget _rays({required Color color, required double intensity, required int rayCount}) => Positioned.fill(
    child: CustomPaint(
      painter: _RaysPainter(
        color: color,
        intensity: intensity,
        rotation: _spin.value * 2 * pi,
        rayCount: rayCount,
        burst: 0,
        sparkle: false,
      ),
    ),
  );

  /// The face down stack, shaking and glowing as it builds up.
  Widget _buildUp() {
    final charge = _charge.value;
    final color = _climb(charge, _best);
    final shake = sin(charge * pi * 18) * charge * (1 + _best.index * 2.5);
    return Stack(
      children: [
        _rays(color: color, intensity: charge, rayCount: 6 + _best.stars * 4),
        Center(
          child: Transform.translate(
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
                      child: CardBack(width: 150, glow: i == 0 ? color.withValues(alpha: charge) : null),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _carousel() {
    final outcomes = widget.outcomes;
    final count = outcomes.length;
    final step = _step.value;
    final turned = Curves.easeInOutCubic.transform(Interval(0, _turnPart).transform(step));
    final held = Interval(_turnPart, 1).transform(step);
    final preview = _stage == _Stage.preview;
    // Card `i` is at the front at position `i`; the second turn goes round
    // once more.
    final position = (preview ? 0 : count) + _index - (1 - turned);
    // The first turn spreads the stack out into the carousel.
    final spread = preview && _index == 0 ? turned : 1.0;

    bool rarityShown(int i) => !preview || i < _index || (i == _index && held > 0);
    double flipped(int i) => preview || i > _index
        ? 0
        : i < _index
        ? 1
        : Curves.easeInOut.transform(Interval(_turnPart, _turnPart + (1 - _turnPart) * 0.6).transform(step));

    final front = _front;
    final frontShown = rarityShown(_index);
    final frontRarity = front.card.rarity;
    return LayoutBuilder(
      builder: (context, constraints) {
        const caption = 96.0;
        final width = min(140.0, min(constraints.maxWidth * 0.34, (constraints.maxHeight - caption) * 0.5 / 1.45));
        final radius = width * 1.6 * spread;
        // Back cards first, so the front one is drawn on top.
        final order = [for (var i = 0; i < count; i++) i]
          ..sort((a, b) => cos(2 * pi * (a - position) / count).compareTo(cos(2 * pi * (b - position) / count)));
        return Stack(
          children: [
            _rays(
              color: frontShown ? frontRarity.color : Colors.white,
              intensity: frontShown ? 0.35 + 0.2 * frontRarity.index : 0.15,
              rayCount: 6 + (frontShown ? frontRarity.stars : 1) * 4,
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: caption,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (final i in order)
                    _carouselCard(
                      outcomes[i],
                      width: width,
                      angle: 2 * pi * (i - position) / count,
                      radius: radius,
                      rarityShown: rarityShown(i),
                      flipped: flipped(i),
                      // The front card's rarity pops as it's shown.
                      pop: i == _index && preview ? held : 1,
                    ),
                ],
              ),
            ),
            Positioned(left: 16, right: 16, bottom: 0, height: caption, child: _caption(front, preview, held)),
          ],
        );
      },
    );
  }

  Widget _carouselCard(
    PullOutcome outcome, {
    required double width,
    required double angle,
    required double radius,
    required bool rarityShown,
    required double flipped,
    required double pop,
  }) {
    final rarity = outcome.card.rarity;
    final facing = cos(angle);
    final turn = angle + flipped * pi;
    // Only a flipped card facing the viewer shows its character.
    final showFront = flipped > 0 && cos(turn) < 0;
    final glow = rarityShown ? rarity.color.withValues(alpha: 0.9 * pop.clamp(0.0, 1.0)) : null;
    final Widget face = showFront
        ? Standee(card: outcome.card, width: width)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  CardBack(width: width, glow: glow),
                  if (rarityShown)
                    Padding(
                      padding: EdgeInsets.only(bottom: width * 0.08),
                      child: Transform.scale(
                        scale: Curves.easeOutBack.transform(pop.clamp(0.0, 1.0)),
                        child: StarRow(rarity: rarity, size: width * 0.14),
                      ),
                    ),
                ],
              ),
              StandeeBase(width: width * 0.62),
            ],
          );
    return Opacity(
      // Cards at the back fade into the dark.
      opacity: 0.3 + 0.7 * (facing + 1) / 2,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          // Seen from a little above, so the ring's far side rises.
          ..rotateX(0.45)
          ..translateByDouble(sin(angle) * radius, 0, radius * (1 - facing), 1)
          ..rotateY(showFront ? turn - pi : turn),
        child: face,
      ),
    );
  }

  /// What the front card shows: its rarity, then its character.
  Widget _caption(PullOutcome front, bool preview, double held) {
    final card = front.card;
    if (preview) {
      if (held == 0) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PoppingStars(rarity: card.rarity, progress: (held * 2).clamp(0.0, 1.0)),
          Text(
            card.rarity.label,
            style: TextStyle(color: card.rarity.color, fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ],
      );
    }
    final shown = const Interval(0.4, 0.7).transform(held);
    if (shown == 0) return const SizedBox.shrink();
    return Opacity(
      opacity: shown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            card.subject,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(
            front.isNew ? 'NEW' : '+1 upgrade',
            style: TextStyle(color: front.isNew ? card.rarity.color : Colors.white60),
          ),
        ],
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
