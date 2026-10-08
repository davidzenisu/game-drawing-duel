import 'dart:math';

import 'package:flutter/material.dart';

import '../logic/themes.dart';

/// Painted scenery for a [DailyTheme] that cross-fades when the theme changes.
class ThemedBackground extends StatelessWidget {
  const ThemedBackground({super.key, required this.theme, required this.child});

  final DailyTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          child: CustomPaint(key: ValueKey(theme), painter: _SceneryPainter(theme), size: Size.infinite),
        ),
        child,
      ],
    );
  }
}

class _SceneryPainter extends CustomPainter {
  _SceneryPainter(this.theme);

  final DailyTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.skyTop, theme.skyBottom],
        ).createShader(rect),
    );

    final random = Random(theme.index);
    if (theme.isDark) {
      final star = Paint()..color = Colors.white.withValues(alpha: 0.8);
      for (var i = 0; i < 70; i++) {
        canvas.drawCircle(
          Offset(random.nextDouble() * size.width, random.nextDouble() * size.height * 0.6),
          random.nextDouble() * 1.6 + 0.4,
          star,
        );
      }
    }

    final sun = Offset(size.width * 0.78, size.height * 0.16);
    canvas.drawCircle(
      sun,
      size.shortestSide * 0.09,
      Paint()
        ..color = theme.accent.withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    for (final (i, color) in theme.hills.indexed) {
      final baseY = size.height * (0.55 + i * 0.13);
      final amplitude = size.height * (0.06 - i * 0.012);
      final phase = random.nextDouble() * pi * 2;
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width; x += 8) {
        final y = baseY + sin(x / size.width * pi * (2 + i) + phase) * amplitude + sin(x / 23 + phase) * 2;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color);

      // Loose hand-drawn hatching on top of each layer.
      final hatch = Paint()
        ..color = Color.lerp(color, Colors.black, 0.25)!.withValues(alpha: 0.5)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      for (var j = 0; j < 26; j++) {
        final x = random.nextDouble() * size.width;
        final y = baseY + amplitude + random.nextDouble() * size.height * 0.1;
        canvas.drawLine(Offset(x, y), Offset(x + 6 + random.nextDouble() * 6, y - 8 - random.nextDouble() * 6), hatch);
      }
    }
  }

  @override
  bool shouldRepaint(_SceneryPainter oldDelegate) => oldDelegate.theme != theme;
}
