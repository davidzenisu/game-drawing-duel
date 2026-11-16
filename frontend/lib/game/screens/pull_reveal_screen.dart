import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/gacha.dart';
import '../rules/models.dart';
import '../rules/upgrades.dart';
import '../widgets/card_art.dart';
import '../widgets/gacha_box.dart';
import '../widgets/sketch_canvas.dart';

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

/// How long a pull takes to come out of its box, from the flaps opening
/// to the box sinking away.
const _pullOutTime = Duration(milliseconds: 1300);

/// The box a [banner]'s pulls come out of: the weekly rate-up's is taped in
/// the legends' gold.
GachaBox _box(
  GachaBanner banner, {
  required double width,
  required GachaBoxLayer layer,
  double open = 0,
  double leak = 0,
  Color glow = Colors.white,
}) => GachaBox(
  width: width,
  layer: layer,
  open: open,
  leak: leak,
  glow: glow,
  tape: banner == GachaBanner.weekly ? Rarity.legend.color : GachaBox.plainTape,
  label: banner == GachaBanner.weekly ? 'WEEKLY HERO' : 'DRAWING DUEL',
);

/// Full screen reveal of pulls, out of a cardboard box. A single pull's box
/// shakes, leaking its rarity's light, opens, and the card rises out, flips
/// and bursts. A multi-pull's cards fan out of the box into a carousel face
/// down, every back glowing in its rarity's colour, then reveal one by one
/// the same way, and it ends on an overview of them all.
class PullRevealScreen extends StatefulWidget {
  const PullRevealScreen({
    super.key,
    required this.outcomes,
    this.owned = const {},
    this.banner = GachaBanner.standard,
  });

  final List<PullOutcome> outcomes;

  /// The banner pulled on, for its box.
  final GachaBanner banner;

  /// Your characters after the pulls, by card id: a duplicate tells
  /// whether its next upgrade is ready. Characters show plain here, so the
  /// drawing stays the focus.
  final Map<String, OwnedCard> owned;

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
                child: _MultiPull(
                  outcomes: widget.outcomes,
                  banner: widget.banner,
                  owned: widget.owned,
                  onReveal: _reveal,
                  onInspect: _inspect,
                  onDone: _close,
                ),
              ),
            if (spotlight != null)
              Positioned.fill(
                child: _SingleReveal(
                  key: ObjectKey(spotlight),
                  outcome: spotlight,
                  banner: widget.banner,
                  owned: widget.owned[spotlight.card.id],
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

/// One character: its box builds up, shaking harder and leaking light that
/// climbs through the rarities' colours, opens, and the card rises out of
/// it towards you, flips and bursts; legends flash. Its stars pop in one by
/// one. Tap to see it all, then to move on.
class _SingleReveal extends StatefulWidget {
  const _SingleReveal({
    super.key,
    required this.outcome,
    required this.banner,
    required this.buildUp,
    required this.onDone,
    this.owned,
    this.progress,
    this.onSkip,
  });

  final PullOutcome outcome;
  final GachaBanner banner;

  /// The pulled character as you own it now, for its upgrade points.
  final OwnedCard? owned;
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
  late final _pull = AnimationController(vsync: this, duration: _pullOutTime);
  late final _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _charge.addStatusListener((status) {
      if (status == AnimationStatus.completed && _pull.isDismissed) _pull.forward();
    });
    _pull.addStatusListener((status) {
      if (status == AnimationStatus.completed && _flip.isDismissed) _flip.forward();
    });
    _flip.addStatusListener((status) {
      if (status == AnimationStatus.completed && _burst.isDismissed) _burst.forward();
    });
    if (widget.buildUp) {
      _charge.forward();
    } else {
      _charge.value = 1;
      _pull.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _showAll();
  }

  void _showAll() {
    _charge.value = 1;
    _pull.value = 1;
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
    _pull.dispose();
    _flip.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rarity = _rarity;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_charge, _pull, _flip, _burst]),
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
                  painter: _GlowPainter(
                    color: color,
                    intensity: charge * 0.5 + burst * 0.5,
                    burst: Curves.easeOut.transform(const Interval(0, 0.6).transform(burst)),
                    sparkle: rarity.stars >= Rarity.hero.stars,
                  ),
                ),
              ),
              Center(child: _pull.isCompleted ? _card(context, color) : _outOfTheBox(color)),
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

  /// The box shaking and leaking light, then opening, the card rising out
  /// of it towards you while the box sinks away.
  Widget _outOfTheBox(Color glow) {
    const boxWidth = 260.0;
    const cardWidth = 200.0;
    final boxHeight = GachaBox.heightFor(boxWidth);
    final charge = _charge.value;
    final pull = _pull.value;
    // The box shakes harder the further the build-up climbs.
    final shake = pull == 0 ? sin(charge * pi * 18) * charge * (1 + _rarity.index * 2.5) : 0.0;
    final tilt = pull == 0 ? sin(charge * pi * 13) * charge * 0.01 * (1 + _rarity.index) : 0.0;
    final open = const Interval(0, 0.3).transform(pull);
    final rise = const Interval(0.2, 0.8, curve: Curves.easeInOutCubic).transform(pull);
    final sink = const Interval(0.55, 1, curve: Curves.easeInCubic).transform(pull);
    // The box sits a little low, so the card has room to rise above it.
    final boxAt = Offset(shake, boxHeight * 0.25 + sink * 600);
    final opening = GachaBox.openingFor(boxWidth) - Offset(boxWidth / 2, boxHeight / 2) + Offset(0, boxHeight * 0.25);
    // Small and deep inside at first, so the front wall hides it.
    const startScale = 0.42;
    final startAt = opening + const Offset(0, cardWidth / cardAspectRatio * startScale * 0.5 + 24);
    final cardAt = Offset.lerp(startAt, Offset.zero, rise)!;
    final scale = startScale + (1 - startScale) * rise;
    Widget box(GachaBoxLayer layer) => Transform.translate(
      offset: boxAt,
      child: Transform.rotate(
        angle: tilt,
        child: Opacity(
          opacity: 1 - sink,
          child: _box(
            widget.banner,
            width: boxWidth,
            layer: layer,
            open: open,
            leak: max(charge, pull > 0 ? 1 : 0),
            glow: glow,
          ),
        ),
      ),
    );
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        box(GachaBoxLayer.back),
        if (pull > 0.2)
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..translateByDouble(cardAt.dx, cardAt.dy, 0, 1)
              // Leaning back as it comes out, then turning to face you.
              ..rotateX((1 - rise) * 0.9)
              ..rotateZ(sin(rise * pi) * 0.12)
              ..scaleByDouble(scale, scale, 1, 1),
            child: CardBack(width: cardWidth, glow: glow),
          ),
        box(GachaBoxLayer.front),
      ],
    );
  }

  Widget _card(BuildContext context, Color glow) {
    final angle = Curves.easeInOut.transform(_flip.value) * pi;
    final showFront = angle > pi / 2;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateY(showFront ? angle - pi : angle),
      child: showFront ? _front(context) : CardBack(width: 200, glow: glow),
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
                if (!outcome.isNew && (widget.owned?.hasUnspentPoints ?? false))
                  const Chip(
                    backgroundColor: AppPalette.victory,
                    avatar: Icon(Icons.auto_fix_high_rounded, color: Colors.white),
                    label: Text('Upgrade ready!', style: TextStyle(color: Colors.white)),
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

/// Several pulls. They come out of their box one after another and spin
/// into a carousel face down, every back lighting up in its rarity's colour
/// at once, then each one gets a reveal of its own in order, and the
/// overview of them all comes last.
class _MultiPull extends StatefulWidget {
  const _MultiPull({
    required this.outcomes,
    required this.banner,
    required this.owned,
    required this.onReveal,
    required this.onInspect,
    required this.onDone,
  });

  final List<PullOutcome> outcomes;
  final GachaBanner banner;
  final Map<String, OwnedCard> owned;

  /// Reveals one card, then calls `next`; `skip` skips the rest.
  final void Function(PullOutcome outcome, String progress, VoidCallback next, VoidCallback skip) onReveal;
  final ValueChanged<PullOutcome> onInspect;
  final VoidCallback onDone;

  @override
  State<_MultiPull> createState() => _MultiPullState();
}

class _MultiPullState extends State<_MultiPull> with TickerProviderStateMixin {
  /// The cards come out of the box, spread out and turn once round while
  /// their backs light up.
  late final _carousel = AnimationController(vsync: this, duration: const Duration(milliseconds: 4400));
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
    // The box opens, the cards rise out of it one after another, and it
    // sinks away.
    final open = const Interval(0, 0.08).transform(t);
    double emerge(int i) =>
        Interval(0.06 + 0.2 * i / count, 0.2 + 0.2 * i / count, curve: Curves.easeOutCubic).transform(t);
    final sink = const Interval(0.32, 0.45, curve: Curves.easeInCubic).transform(t);
    final spread = const Interval(0.1, 0.45, curve: Curves.easeOutBack).transform(t);
    // One turn round, slowing down until the first card is at the front.
    final position = -count * (1 - Curves.easeOutCubic.transform(t));
    // All backs light up together, then pulse gently.
    final glow = const Interval(0.3, 0.7, curve: Curves.easeIn).transform(t);
    final pulse = 0.85 + 0.15 * sin(_spin.value * 2 * pi * 6);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The ring is about 3.5 cards wide, so it fits the screen.
        final width = min(140.0, min(constraints.maxWidth * 0.26, constraints.maxHeight * 0.5 / 1.45));
        final radius = width * 1.6 * spread;
        double angle(int i) => 2 * pi * (i - position) / count;
        // Back cards first, so the front one is drawn on top.
        final order = [for (var i = 0; i < count; i++) i]..sort((a, b) => cos(angle(a)).compareTo(cos(angle(b))));
        final boxWidth = width * 2;
        final boxHeight = GachaBox.heightFor(boxWidth);
        // Below the ring, and sinking out of sight once empty.
        final boxAt = Offset(0, constraints.maxHeight / 2 - boxHeight / 2 - 8 + sink * constraints.maxHeight);
        final opening = GachaBox.openingFor(boxWidth) - Offset(boxWidth / 2, boxHeight / 2) + boxAt;
        Widget box(GachaBoxLayer layer) => Transform.translate(
          offset: boxAt,
          child: Opacity(
            opacity: 1 - sink,
            child: _box(widget.banner, width: boxWidth, layer: layer, open: open, leak: open, glow: Colors.white),
          ),
        );
        // Just the dark background, so the glows stand out.
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (sink < 1) box(GachaBoxLayer.back),
            for (final i in order)
              if (emerge(i) > 0)
                Transform.translate(
                  // From deep in the box up into the ring, growing as it
                  // comes towards you.
                  offset: Offset.lerp(opening + Offset(0, width * 0.5), Offset.zero, emerge(i))!,
                  child: Transform.scale(
                    scale: 0.45 + 0.55 * emerge(i),
                    child: _ringCard(outcomes[i], width: width, angle: angle(i), radius: radius, glow: glow * pulse),
                  ),
                ),
            if (sink < 1) box(GachaBoxLayer.front),
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
                              outcome.isNew
                                  ? 'NEW'
                                  : widget.owned[outcome.card.id]?.hasUnspentPoints ?? false
                                  ? 'Upgrade ready!'
                                  : '+1 upgrade',
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

/// A soft glow in the rarity's colour behind a reveal, and the ring (and
/// for rare ones the sparkles) it bursts into.
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.color, required this.intensity, required this.burst, required this.sparkle});

  final Color color;
  final double intensity;
  final double burst;
  final bool sparkle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      size.shortestSide * (0.2 + 0.25 * intensity),
      Paint()
        ..color = color.withValues(alpha: 0.6 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );
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
  bool shouldRepaint(_GlowPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.intensity != intensity ||
      oldDelegate.burst != burst ||
      oldDelegate.sparkle != sparkle;
}
