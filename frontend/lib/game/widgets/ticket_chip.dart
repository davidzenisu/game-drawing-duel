import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/palette.dart';

/// Shows the number of available gacha pulls and pops when it changes.
///
/// New pulls are celebrated: a big ticket with the pulls received rises in
/// the middle of a darkened screen, then flies into the chip, whose count
/// only goes up once it lands. Pulls that arrive while the chip's screen is
/// covered (e.g. the pull a drawing earns) are celebrated once you're back.
class TicketChip extends StatefulWidget {
  const TicketChip({super.key, required this.tickets});

  final int tickets;

  @override
  State<TicketChip> createState() => _TicketChipState();
}

class _TicketChipState extends State<TicketChip> {
  /// The count last celebrated by any chip, so a chip on a screen below
  /// doesn't celebrate the same pulls again once you go back to it.
  static int? _celebrated;

  late int _shown = widget.tickets;
  bool _playing = false;
  ValueListenable<TickerModeData>? _tickerMode;

  @override
  void initState() {
    super.initState();
    _celebrated = widget.tickets;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covered screens have their tickers off: wait until it's shown again.
    final mode = TickerMode.getValuesNotifier(context);
    if (mode != _tickerMode) {
      _tickerMode?.removeListener(_celebrateLater);
      _tickerMode = mode..addListener(_celebrateLater);
    }
  }

  @override
  void didUpdateWidget(TicketChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tickets < oldWidget.tickets) {
      // Spent: no celebration, and later gains count from here.
      _celebrated = min<int>(_celebrated ?? widget.tickets, widget.tickets);
      if (!_playing) _shown = widget.tickets;
    } else if (widget.tickets > oldWidget.tickets) {
      _celebrateLater();
    }
  }

  /// After the frame, once the chip has its place on screen.
  void _celebrateLater() => WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate());

  @override
  void dispose() {
    _tickerMode?.removeListener(_celebrateLater);
    super.dispose();
  }

  void _celebrate() {
    if (!mounted || _playing) return;
    final target = widget.tickets;
    if (target <= _shown) return;
    final gained = target - max<int>(_shown, _celebrated ?? _shown);
    if (gained <= 0 || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      // Already celebrated elsewhere, or animations are off.
      _celebrated = max<int>(_celebrated ?? target, target);
      setState(() => _shown = target);
      return;
    }
    if (!TickerMode.valuesOf(context).enabled) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final chip = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null || chip == null || overlayBox == null || !chip.attached) {
      setState(() => _shown = target);
      return;
    }
    _celebrated = target;
    _playing = true;
    final into = chip.localToGlobal(chip.size.center(Offset.zero), ancestor: overlayBox);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => PullsReceived(
        pulls: gained,
        into: into,
        onDone: () {
          entry.remove();
          if (!mounted) return;
          setState(() {
            _playing = false;
            _shown = target;
          });
          // More may have come in meanwhile.
          _celebrateLater();
        },
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.confirmation_number_rounded, color: AppPalette.ticket),
      label: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
          child: child,
        ),
        child: Text('$_shown pulls', key: ValueKey(_shown)),
      ),
    );
  }
}

/// The celebration of new pulls: a big glowing ticket with "+N pulls" pops up
/// in the middle of a darkened screen, then shrinks into [into], where the
/// pulls chip sits. Taps go through, so it never gets in the way.
class PullsReceived extends StatefulWidget {
  const PullsReceived({super.key, required this.pulls, required this.into, required this.onDone});

  final int pulls;

  /// Where the ticket flies to, in the overlay's coordinates.
  final Offset into;
  final VoidCallback onDone;

  static const duration = Duration(milliseconds: 2000);

  @override
  State<PullsReceived> createState() => _PullsReceivedState();
}

class _PullsReceivedState extends State<PullsReceived> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: PullsReceived.duration)
    ..forward().whenComplete(widget.onDone);

  // Darkens, pops up, holds, then flies into the chip as the screen clears.
  late final _scrim = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 53),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 35),
  ]).animate(_controller);
  late final _pop = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.05, 0.35, curve: Curves.elasticOut),
  );
  late final _fly = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.65, 0.95, curve: Curves.easeInCubic),
  );
  late final _label = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.6, 0.72, curve: Curves.easeIn),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = '+${widget.pulls} ${widget.pulls == 1 ? 'pull' : 'pulls'}';
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: '$label received',
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final middle = constraints.biggest.center(Offset.zero);
              final at = Offset.lerp(middle, widget.into, _fly.value)!;
              final scale = _pop.value * (1 - 0.85 * _fly.value);
              return Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(color: Colors.black.withValues(alpha: 0.6 * _scrim.value)),
                  ),
                  Positioned(
                    left: at.dx - 120,
                    top: at.dy - 120,
                    width: 240,
                    height: 240,
                    child: Transform.scale(
                      scale: max(scale, 0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 150,
                            height: 150,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Rays turning behind the ticket.
                                Transform.rotate(
                                  angle: _controller.value * pi,
                                  child: CustomPaint(
                                    size: const Size.square(150),
                                    painter: _Rays(color: AppPalette.rarityLegend.withValues(alpha: 0.55)),
                                  ),
                                ),
                                Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppPalette.rarityLegend.withValues(alpha: 0.8),
                                        blurRadius: 32,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.confirmation_number_rounded,
                                    size: 60,
                                    color: AppPalette.ticket,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Opacity(
                            opacity: 1 - _label.value,
                            child: Text(
                              label,
                              style: text.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A burst of rays, like light behind a prize.
class _Rays extends CustomPainter {
  _Rays({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    const rays = 12;
    for (var i = 0; i < rays; i++) {
      final a = i * 2 * pi / rays;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + radius * cos(a - 0.12), center.dy + radius * sin(a - 0.12))
        ..lineTo(center.dx + radius * cos(a + 0.12), center.dy + radius * sin(a + 0.12))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_Rays oldDelegate) => oldDelegate.color != color;
}
