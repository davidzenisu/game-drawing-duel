import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../logic/models.dart';
import '../logic/upgrades.dart';

Color elementColor(ElementKind element) => switch (element) {
  ElementKind.fire => AppPalette.elementFire,
  ElementKind.ice => AppPalette.elementIce,
  ElementKind.storm => AppPalette.elementStorm,
};

/// Renders a sketch with the upgrade effects applied to its brush strokes:
/// ink shadows, glowing lines, elemental particles rising off the strokes,
/// energy flowing along them and a golden shimmer.
class EffectSketchView extends StatefulWidget {
  const EffectSketchView({
    super.key,
    required this.sketch,
    required this.effects,
    this.element,
    this.accent = AppPalette.rarityHero,
  });

  final Sketch sketch;
  final List<UpgradeEffect> effects;
  final ElementKind? element;

  /// Glow colour when no element was chosen.
  final Color accent;

  @override
  State<EffectSketchView> createState() => _EffectSketchViewState();
}

class _EffectSketchViewState extends State<EffectSketchView> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late _StrokeSamples _samples = _StrokeSamples(widget.sketch);

  bool get _animated => widget.effects.any((e) => e != UpgradeEffect.shadow);

  @override
  void initState() {
    super.initState();
    if (_animated) _controller.repeat();
  }

  @override
  void didUpdateWidget(EffectSketchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sketch != widget.sketch) _samples = _StrokeSamples(widget.sketch);
    if (_animated && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_animated && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _EffectPainter(
          animation: _controller,
          sketch: widget.sketch,
          samples: _samples,
          effects: widget.effects.toSet(),
          element: widget.element,
          accent: widget.accent,
        ),
      ),
    );
  }
}

/// Points along all strokes, normalised, used to emit particles.
class _StrokeSamples {
  _StrokeSamples(Sketch sketch) {
    final all = <Offset>[];
    for (final stroke in sketch.strokes) {
      for (var i = 0; i < stroke.points.length; i++) {
        if (i == 0 || (stroke.points[i] - all.last).distance > 0.02) all.add(stroke.points[i]);
      }
      ends.addAll([stroke.points.first, stroke.points.last]);
    }
    // Keep painting cheap for busy drawings.
    final step = max(1, all.length ~/ 90);
    points = [for (var i = 0; i < all.length; i += step) all[i]];
  }

  late final List<Offset> points;
  final List<Offset> ends = [];
}

class _EffectPainter extends CustomPainter {
  _EffectPainter({
    required this.animation,
    required this.sketch,
    required this.samples,
    required this.effects,
    required this.element,
    required this.accent,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Sketch sketch;
  final _StrokeSamples samples;
  final Set<UpgradeEffect> effects;
  final ElementKind? element;
  final Color accent;

  Color get _glow => element != null ? elementColor(element!) : accent;

  /// Stable pseudo random value in [0, 1) per index.
  double _hash(int i) {
    final v = sin(i * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  Path _path(Stroke stroke, Size size) {
    final points = [for (final p in stroke.points) Offset(p.dx * size.width, p.dy * size.height)];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) return path..lineTo(points.first.dx + 0.1, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    return path..lineTo(points.last.dx, points.last.dy);
  }

  Paint _strokePaint(Stroke stroke, Size size, {Color? color, double widthFactor = 1, double blur = 0}) {
    final paint = Paint()
      ..color = color ?? stroke.color
      ..strokeWidth = stroke.width * size.width * widthFactor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    return paint;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final paths = [for (final s in sketch.strokes) _path(s, size)];
    final pulse = 0.65 + 0.35 * sin(t * 2 * pi);

    // Shadow: the ink casts a soft shadow onto the cardboard.
    if (effects.contains(UpgradeEffect.shadow)) {
      canvas.save();
      canvas.translate(size.width * 0.025, size.width * 0.035);
      for (final (i, stroke) in sketch.strokes.indexed) {
        canvas.drawPath(
          paths[i],
          _strokePaint(stroke, size, color: Colors.black.withValues(alpha: 0.35), widthFactor: 1.6, blur: 3),
        );
      }
      canvas.restore();
    }

    // Light: the strokes glow from behind.
    if (effects.contains(UpgradeEffect.light)) {
      for (final (i, stroke) in sketch.strokes.indexed) {
        canvas.drawPath(
          paths[i],
          _strokePaint(stroke, size, color: _glow.withValues(alpha: 0.55 * pulse), widthFactor: 5, blur: 6),
        );
      }
    }

    // Element: the ink itself burns, freezes or crackles.
    final hasElement = effects.contains(UpgradeEffect.element) && element != null;
    final storming = hasElement && element == ElementKind.storm && (t * 14).floor().isEven;
    if (hasElement) {
      final strength = effects.contains(UpgradeEffect.aura) ? 1.0 : 0.75;
      for (final (i, stroke) in sketch.strokes.indexed) {
        canvas.drawPath(
          paths[i],
          _strokePaint(
            stroke,
            size,
            color: _glow.withValues(alpha: (storming ? 0.95 : 0.7 * pulse) * strength),
            widthFactor: 3.2,
            blur: 3,
          ),
        );
      }
    }

    // The drawing itself.
    for (final (i, stroke) in sketch.strokes.indexed) {
      canvas.drawPath(paths[i], _strokePaint(stroke, size));
    }
    if (hasElement && element == ElementKind.fire) {
      // A flickering ember core inside every line.
      for (final (i, stroke) in sketch.strokes.indexed) {
        final flicker = 0.5 + 0.5 * sin(t * 2 * pi * 3 + i);
        canvas.drawPath(
          paths[i],
          _strokePaint(
            stroke,
            size,
            color: Color.lerp(AppPalette.elementFire, const Color(0xFFFFE066), flicker)!,
            widthFactor: 0.45,
          ),
        );
      }
    }
    if (storming) {
      for (final (i, stroke) in sketch.strokes.indexed) {
        canvas.drawPath(
          paths[i],
          _strokePaint(stroke, size, color: Colors.white.withValues(alpha: 0.85), widthFactor: 0.4),
        );
      }
    }
    if (element == ElementKind.ice && hasElement) {
      for (final (i, stroke) in sketch.strokes.indexed) {
        canvas.drawPath(
          paths[i],
          _strokePaint(stroke, size, color: Colors.white.withValues(alpha: 0.7), widthFactor: 0.35),
        );
      }
    }

    // Aura: pulses of energy run along every stroke.
    if (effects.contains(UpgradeEffect.aura)) {
      for (final (i, stroke) in sketch.strokes.indexed) {
        for (final metric in paths[i].computeMetrics()) {
          final length = metric.length;
          final start = ((t * 1.5 + _hash(i)) % 1.0) * length;
          final segment = metric.extractPath(start, min(length, start + max(12, length * 0.25)));
          canvas.drawPath(segment, _strokePaint(stroke, size, color: _glow, widthFactor: 3, blur: 4));
          canvas.drawPath(segment, _strokePaint(stroke, size, color: Colors.white, widthFactor: 1.2));
        }
      }
    }

    if (effects.contains(UpgradeEffect.element) && element != null) {
      switch (element!) {
        case ElementKind.fire:
          _paintFire(canvas, size, t, strong: effects.contains(UpgradeEffect.aura));
        case ElementKind.ice:
          _paintIce(canvas, size, t, strong: effects.contains(UpgradeEffect.aura));
        case ElementKind.storm:
          _paintStorm(canvas, size, t, strong: effects.contains(UpgradeEffect.aura));
      }
    }

    // Halo: a golden shimmer sweeps across the ink, sparkles at stroke ends.
    if (effects.contains(UpgradeEffect.halo)) {
      final band = t * 2.4 - 0.7;
      final shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Colors.transparent,
          AppPalette.rarityLegend,
          Colors.white,
          AppPalette.rarityLegend,
          Colors.transparent,
        ],
        stops: [band - 0.15, band - 0.05, band, band + 0.05, band + 0.15].map((s) => s.clamp(0.0, 1.0)).toList(),
      ).createShader(Offset.zero & size);
      for (final (i, stroke) in sketch.strokes.indexed) {
        canvas.drawPath(paths[i], _strokePaint(stroke, size, widthFactor: 1.8)..shader = shader);
      }
      for (final (i, end) in samples.ends.indexed) {
        final phase = (t * 2 + _hash(i + 7)) % 1.0;
        final twinkle = sin(phase * pi);
        _sparkle(
          canvas,
          Offset(end.dx * size.width, end.dy * size.height),
          size.width * 0.035 * twinkle,
          Colors.white.withValues(alpha: twinkle),
        );
      }
    }
  }

  void _paintFire(Canvas canvas, Size size, double t, {required bool strong}) {
    final points = samples.points;
    final perPoint = strong ? 3 : 2;
    for (var i = 0; i < points.length; i++) {
      for (var k = 0; k < perPoint; k++) {
        final phase = (t * (1.8 + k * 0.6) + _hash(i * 5 + k)) % 1.0;
        final base = Offset(points[i].dx * size.width, points[i].dy * size.height);
        final rise = phase * size.height * (strong ? 0.22 : 0.15);
        final sway = sin(phase * 8 + i + k) * size.width * 0.018;
        final height = size.width * (strong ? 0.09 : 0.065) * (1 - phase * 0.7);
        final tip = base + Offset(sway, -rise);
        final color = Color.lerp(
          const Color(0xFFFFE066),
          AppPalette.elementFire,
          phase * 1.4 > 1 ? 1 : phase * 1.4,
        )!.withValues(alpha: 0.85 * (1 - phase));
        _flame(canvas, tip, height, color);
      }
    }
  }

  /// A teardrop flame with its point upwards and a bright core.
  void _flame(Canvas canvas, Offset bottom, double height, Color color) {
    final w = height * 0.42;
    final path = Path()
      ..moveTo(bottom.dx, bottom.dy - height)
      ..quadraticBezierTo(bottom.dx + w * 1.2, bottom.dy - height * 0.35, bottom.dx, bottom.dy)
      ..quadraticBezierTo(bottom.dx - w * 1.2, bottom.dy - height * 0.35, bottom.dx, bottom.dy - height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawCircle(
      bottom + Offset(0, -height * 0.28),
      w * 0.45,
      Paint()..color = Colors.white.withValues(alpha: color.a * 0.7),
    );
  }

  void _paintIce(Canvas canvas, Size size, double t, {required bool strong}) {
    final points = samples.points;
    final every = strong ? 2 : 4;
    for (var i = 0; i < points.length; i += every) {
      final phase = (t * 1.2 + _hash(i)) % 1.0;
      final scale = sin(phase * pi);
      final center = Offset(points[i].dx * size.width, points[i].dy * size.height);
      _crystal(canvas, center, size.width * (strong ? 0.05 : 0.035) * scale, phase * pi, AppPalette.elementIce);
    }
    // Snow drifting down over the card.
    final flakes = strong ? 24 : 12;
    for (var i = 0; i < flakes; i++) {
      final phase = (t + _hash(i + 100)) % 1.0;
      final x = (_hash(i + 200) + sin(phase * 4 + i) * 0.03) * size.width;
      canvas.drawCircle(
        Offset(x, phase * size.height),
        size.width * 0.008,
        Paint()..color = Colors.white.withValues(alpha: 0.9 * sin(phase * pi)),
      );
    }
  }

  void _paintStorm(Canvas canvas, Size size, double t, {required bool strong}) {
    final points = samples.points;
    if (points.length < 2) return;
    // Lightning jumps between nearby points of the drawing, a few times a second.
    final step = (t * 14).floor();
    final rng = Random(step);
    final bolts = strong ? 7 : 4;
    for (var b = 0; b < bolts; b++) {
      final from = points[rng.nextInt(points.length)];
      final to = points[rng.nextInt(points.length)];
      if ((from - to).distance > 0.6) continue;
      final a = Offset(from.dx * size.width, from.dy * size.height);
      final z = Offset(to.dx * size.width, to.dy * size.height);
      final bolt = Path()..moveTo(a.dx, a.dy);
      const segments = 6;
      for (var s = 1; s < segments; s++) {
        final p = Offset.lerp(a, z, s / segments)!;
        bolt.lineTo(
          p.dx + (rng.nextDouble() - 0.5) * size.width * 0.06,
          p.dy + (rng.nextDouble() - 0.5) * size.width * 0.06,
        );
      }
      bolt.lineTo(z.dx, z.dy);
      canvas.drawPath(
        bolt,
        Paint()
          ..color = AppPalette.elementStorm
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.035
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        bolt,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.01,
      );
    }
    // Static crackling on the strokes.
    for (var i = 0; i < points.length; i += strong ? 2 : 4) {
      if (rng.nextDouble() > 0.4) continue;
      final c = Offset(points[i].dx * size.width, points[i].dy * size.height);
      canvas.drawCircle(c, size.width * 0.012, Paint()..color = AppPalette.elementStorm.withValues(alpha: 0.9));
    }
  }

  void _sparkle(Canvas canvas, Offset center, double radius, Color color) {
    if (radius <= 0) return;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      final r = i.isEven ? radius : radius * 0.25;
      final p = center + Offset(cos(angle), sin(angle)) * r;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  void _crystal(Canvas canvas, Offset center, double radius, double rotation, Color color) {
    if (radius <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = max(1, radius * 0.18)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final angle = rotation + i * pi / 3;
      final dir = Offset(cos(angle), sin(angle));
      canvas.drawLine(center, center + dir * radius, paint);
      final branch = center + dir * radius * 0.55;
      canvas.drawLine(branch, branch + Offset(cos(angle + 0.7), sin(angle + 0.7)) * radius * 0.3, paint);
      canvas.drawLine(branch, branch + Offset(cos(angle - 0.7), sin(angle - 0.7)) * radius * 0.3, paint);
    }
  }

  @override
  bool shouldRepaint(_EffectPainter oldDelegate) =>
      oldDelegate.sketch != sketch ||
      oldDelegate.element != element ||
      oldDelegate.accent != accent ||
      !setEquals(oldDelegate.effects, effects);
}
