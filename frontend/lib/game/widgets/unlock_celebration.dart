import 'dart:math';

import 'package:flutter/material.dart';

/// Celebrates an unlocked upgrade around [child]: it pops, sparkles burst
/// out in [color] with a ring, and [label] floats up and fades. Plays every
/// time [count] goes up.
class UnlockCelebration extends StatefulWidget {
  const UnlockCelebration({
    super.key,
    required this.count,
    required this.color,
    required this.label,
    required this.child,
  });

  final int count;
  final Color color;
  final String label;
  final Widget child;

  @override
  State<UnlockCelebration> createState() => _UnlockCelebrationState();
}

class _UnlockCelebrationState extends State<UnlockCelebration> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didUpdateWidget(UnlockCelebration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > oldWidget.count) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        final playing = _controller.isAnimating;
        // A quick pop in the first fifth, settling back.
        final pop = t < 0.2 ? sin(t / 0.2 * pi) * 0.12 : 0.0;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.scale(scale: 1 + pop, child: child),
            if (playing)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BurstPainter(t: t, color: widget.color),
                  ),
                ),
              ),
            if (playing)
              Positioned(
                // Floats up from the top of the card, staying in view.
                top: 56 - 52 * Curves.easeOut.transform(t),
                child: Opacity(
                  opacity: (t < 0.1 ? t / 0.1 : 1 - (t - 0.6).clamp(0, 0.4) / 0.4).clamp(0.0, 1.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 12)],
                    ),
                    child: Text(
                      widget.label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final reach = size.shortestSide * 0.75;
    final eased = Curves.easeOutCubic.transform(t);
    final fade = (1 - t).clamp(0.0, 1.0);

    // A glow flashing up behind the character.
    if (t < 0.35) {
      final flash = sin(t / 0.35 * pi);
      canvas.drawCircle(
        center,
        reach * 0.8,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.45 * flash),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: reach * 0.8)),
      );
    }

    // A ring sweeping outwards.
    canvas.drawCircle(
      center,
      reach * eased,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 * fade
        ..color = color.withValues(alpha: 0.8 * fade),
    );

    // Sparkles flying out, each at its own angle and speed.
    final random = Random(3);
    for (var i = 0; i < 28; i++) {
      final angle = i / 28 * 2 * pi + random.nextDouble() * 0.3;
      final speed = 0.55 + random.nextDouble() * 0.45;
      final position = center + Offset(cos(angle), sin(angle)) * reach * eased * speed;
      final radius = (5 + random.nextDouble() * 6) * fade;
      final sparkle = i.isEven ? color : Colors.white;
      _star(canvas, position, radius * 1.6, sparkle.withValues(alpha: fade));
    }
  }

  void _star(Canvas canvas, Offset center, double radius, Color color) {
    if (radius <= 0) return;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      final r = i.isEven ? radius : radius * 0.35;
      final p = center + Offset(cos(angle), sin(angle)) * r;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}
