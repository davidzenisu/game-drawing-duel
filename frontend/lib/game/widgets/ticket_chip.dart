import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/daily_loop.dart';

/// Shows the number of available gacha pulls and pops when it changes. A
/// tap opens a menu under it with your [stars], the currency.
///
/// New pulls and stars are celebrated: a big ticket (or star) with what was
/// received rises in the middle of a darkened screen, then flies into the
/// chip, whose count only goes up once it lands. Pulls and stars received
/// together are celebrated together. Ones that arrive while the chip's
/// screen is covered (e.g. what a drawing earns) are celebrated once you're
/// back and the page on top is gone. Landed, the count goes up one pull at a
/// time. Spending them is not celebrated.
class TicketChip extends StatefulWidget {
  const TicketChip({super.key, required this.tickets, this.stars = 0, this.onBuyPull});

  final int tickets;

  /// Your stars, shown in the menu under the chip.
  final int stars;

  /// Buys a pull with stars, from the menu; without it, or while you have
  /// pulls or too few stars, the menu only says how it works.
  final VoidCallback? onBuyPull;

  bool get _canBuyPull => onBuyPull != null && tickets == 0 && stars >= StarRewards.pullPrice;

  @override
  State<TicketChip> createState() => _TicketChipState();
}

class _TicketChipState extends State<TicketChip> with SingleTickerProviderStateMixin {
  /// The counts last celebrated by any chip, so a chip on a screen below
  /// doesn't celebrate the same pulls and stars again once you go back to it.
  static int? _celebrated;
  static int? _celebratedStars;

  late int _shown;
  late int _shownStars;
  bool _playing = false;
  ValueListenable<TickerModeData>? _tickerMode;
  Animation<double>? _covered;

  /// Counts the chip up one pull at a time once the ticket lands.
  late final AnimationController _count;

  @override
  void initState() {
    super.initState();
    // Set right away: a lazy start would only be read after a change.
    _shown = _celebrated = widget.tickets;
    _shownStars = _celebratedStars = widget.stars;
    _count = AnimationController(vsync: this);
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
    // A page on top (or one sliding away) moves this one: wait until it's
    // gone, so the ticket lands where the chip ends up. Popups like the
    // notification board don't move it.
    final covered = ModalRoute.of(context)?.secondaryAnimation;
    if (covered != _covered) {
      _covered?.removeStatusListener(_onCovered);
      _covered = covered?..addStatusListener(_onCovered);
    }
  }

  void _onCovered(AnimationStatus status) {
    if (status.isDismissed) _celebrateLater();
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
    if (widget.stars < oldWidget.stars) {
      _celebratedStars = min<int>(_celebratedStars ?? widget.stars, widget.stars);
      if (!_playing) _shownStars = widget.stars;
    } else if (widget.stars > oldWidget.stars) {
      _celebrateLater();
    }
  }

  /// After the frame, once the chip has its place on screen.
  void _celebrateLater() => WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate());

  @override
  void dispose() {
    _tickerMode?.removeListener(_celebrateLater);
    _covered?.removeStatusListener(_onCovered);
    _count.dispose();
    super.dispose();
  }

  /// Whether the chip's screen is showing and still: not covered by another
  /// page, nor moving as one comes or goes.
  bool get _onScreen => TickerMode.valuesOf(context).enabled && (_covered?.isDismissed ?? true);

  /// The chip's middle in [overlay]'s coordinates, while it's on screen.
  Offset? _center(OverlayState overlay) {
    if (!mounted) return null;
    final chip = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (chip == null || overlayBox == null || !chip.attached || !chip.hasSize) return null;
    return chip.localToGlobal(chip.size.center(Offset.zero), ancestor: overlayBox);
  }

  void _celebrate() {
    if (!mounted || _playing) return;
    final target = widget.tickets;
    final targetStars = widget.stars;
    if (target <= _shown && targetStars <= _shownStars) return;
    final gained = max<int>(0, target - max<int>(_shown, _celebrated ?? _shown));
    final gainedStars = max<int>(0, targetStars - max<int>(_shownStars, _celebratedStars ?? _shownStars));
    void showAll() {
      _celebrated = max<int>(_celebrated ?? target, target);
      _celebratedStars = max<int>(_celebratedStars ?? targetStars, targetStars);
      setState(() {
        _shown = max(_shown, target);
        _shownStars = max(_shownStars, targetStars);
      });
    }

    if ((gained == 0 && gainedStars == 0) || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      // Already celebrated elsewhere, or animations are off.
      showAll();
      return;
    }
    if (!_onScreen) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    var into = overlay == null ? null : _center(overlay);
    if (overlay == null || into == null) {
      showAll();
      return;
    }
    _celebrated = max<int>(_celebrated ?? target, target);
    _celebratedStars = max<int>(_celebratedStars ?? targetStars, targetStars);
    _playing = true;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => PullsReceived(
        pulls: gained,
        stars: gainedStars,
        // Follows the chip, should the app bar change meanwhile.
        into: () => into = _center(overlay) ?? into!,
        onDone: () {
          entry.remove();
          _shownStars = max(_shownStars, targetStars);
          _countUp(max(_shown, target));
        },
      ),
    );
    overlay.insert(entry);
  }

  /// Counts the chip up to [target] one pull at a time, slow enough to see
  /// each one (and a bit faster past a dozen).
  Future<void> _countUp(int target) async {
    if (!mounted) return;
    final from = _shown;
    final steps = target - from;
    void step() {
      final n = from + (steps * _count.value).ceil();
      if (n != _shown) setState(() => _shown = n);
    }

    _count
      ..duration = PullsReceived.countStep * min(steps, 12)
      ..addListener(step);
    try {
      await _count.forward(from: 0).orCancel;
    } on TickerCanceled {
      // Disposed meanwhile.
    }
    _count.removeListener(step);
    if (!mounted) return;
    setState(() {
      _playing = false;
      _shown = max(_shown, target);
    });
    // More may have come in meanwhile.
    _celebrateLater();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: 'Pulls and stars',
      position: PopupMenuPosition.under,
      onSelected: (buy) {
        if (buy) widget.onBuyPull?.call();
      },
      itemBuilder: (_) => [
        // A tap on it just closes the menu.
        PopupMenuItem<bool>(value: false, child: _StarsInfo(stars: widget.stars)),
        const PopupMenuDivider(),
        PopupMenuItem<bool>(
          value: true,
          enabled: widget._canBuyPull,
          child: _BuyPull(note: widget.tickets > 0 ? 'Once your pulls are used up' : null),
        ),
      ],
      child: _chip(),
    );
  }

  Widget _chip() {
    return Chip(
      avatar: const Icon(Icons.confirmation_number_rounded, color: AppPalette.ticket),
      label: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
          child: child,
        ),
        child: Text('$_shown pulls', key: ValueKey(_shown)),
      ),
    );
  }
}

/// Your stars: the menu under the pulls chip. What earns them is in the
/// intros (`Tutorial.welcome`).
class _StarsInfo extends StatelessWidget {
  const _StarsInfo({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Like the pulls chip's label and icon.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 18, color: AppPalette.star),
        const SizedBox(width: 8),
        Text(
          '$stars ${stars == 1 ? 'star' : 'stars'}',
          style: (theme.chipTheme.labelStyle ?? theme.textTheme.labelLarge)?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Buying a pull with stars, in the menu under the pulls chip: in the
/// pulls' font, like the stars.
class _BuyPull extends StatelessWidget {
  const _BuyPull({this.note});

  /// Why it can't be bought yet.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.confirmation_number_rounded, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Buy a pull · ${StarRewards.pullPrice} stars',
                style: theme.chipTheme.labelStyle ?? theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
        if (note case final note?) Text(note, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// The celebration of new pulls and stars: a big glowing ticket with
/// "+N pulls" (a star with "+N stars", or both side by side with
/// "+N pulls · +N stars") pops up in the middle of a darkened screen, then
/// shrinks into [into], where the pulls chip sits. Taps go through, so it
/// never gets in the way.
class PullsReceived extends StatefulWidget {
  const PullsReceived({super.key, this.pulls = 0, this.stars = 0, required this.into, required this.onDone});

  final int pulls;
  final int stars;

  /// Where it flies to, in the overlay's coordinates: asked every frame, so
  /// it follows the chip.
  final Offset Function() into;
  final VoidCallback onDone;

  static const duration = Duration(milliseconds: 2000);

  /// How long the chip takes per pull to count up once the ticket lands.
  static const countStep = Duration(milliseconds: 250);

  /// E.g. "+1 pull", "+3 stars" or "+1 pull · +3 stars".
  static String label({required int pulls, required int stars}) => [
    if (pulls > 0) '+$pulls ${pulls == 1 ? 'pull' : 'pulls'}',
    if (stars > 0) '+$stars ${stars == 1 ? 'star' : 'stars'}',
  ].join(' · ');

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

  /// A glowing white disc with [icon] in [color].
  Widget _token(IconData icon, Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      boxShadow: [BoxShadow(color: AppPalette.rarityLegend.withValues(alpha: 0.8), blurRadius: 32, spreadRadius: 4)],
    ),
    child: Icon(icon, size: size * 0.62, color: color),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = PullsReceived.label(pulls: widget.pulls, stars: widget.stars);
    final both = widget.pulls > 0 && widget.stars > 0;
    final tokens = [
      if (widget.pulls > 0) _token(Icons.confirmation_number_rounded, AppPalette.ticket, both ? 76 : 96),
      if (widget.stars > 0) _token(Icons.star_rounded, AppPalette.star, both ? 76 : 96),
    ];
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: '$label received',
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final middle = constraints.biggest.center(Offset.zero);
              final at = Offset.lerp(middle, widget.into(), _fly.value)!;
              final scale = _pop.value * (1 - 0.85 * _fly.value);
              return Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(color: Colors.black.withValues(alpha: 0.6 * _scrim.value)),
                  ),
                  Positioned(
                    left: at.dx - 160,
                    top: at.dy - 120,
                    width: 320,
                    height: 240,
                    child: Transform.scale(
                      scale: max(scale, 0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 150,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Rays turning behind the prize.
                                Transform.rotate(
                                  angle: _controller.value * pi,
                                  child: CustomPaint(
                                    size: const Size.square(150),
                                    painter: _Rays(color: AppPalette.rarityLegend.withValues(alpha: 0.55)),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final (i, token) in tokens.indexed) ...[
                                      if (i > 0) const SizedBox(width: 12),
                                      token,
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Opacity(
                            opacity: 1 - _label.value,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                style: text.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                                ),
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
