import 'dart:math';

import 'package:flutter/material.dart';

/// The two halves of a [GachaBox], so a card can be drawn coming out of it:
/// the [back] (its inside, the top and the flaps behind) under the card, the
/// [front] (its outer walls and the front flap) over it.
enum GachaBoxLayer { back, front }

/// The cardboard box pulls come out of, seen from a little above and to the
/// left. Its four flaps fold open with [open]; until then, taped shut, it
/// leaks [leak] of [glow]'s light through its seams.
class GachaBox extends StatelessWidget {
  const GachaBox({
    super.key,
    required this.width,
    required this.layer,
    this.open = 0,
    this.leak = 0,
    this.glow = Colors.white,
    this.tape = GachaBox.plainTape,
    this.label = 'DRAWING DUEL',
  });

  /// Its height for a [width].
  static double heightFor(double width) => width * 0.92;

  /// Where the middle of its opening is, from its top left corner, for a
  /// [width]: where cards come out.
  static Offset openingFor(double width) {
    final g = _Geometry(Size(width, heightFor(width)));
    return g.top(g.frontWidth / 2, g.depth / 2);
  }

  static const plainTape = Color(0xFFE6D3A8);

  final double width;
  final GachaBoxLayer layer;
  final double open;
  final double leak;
  final Color glow;
  final Color tape;
  final String label;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, heightFor(width)),
    painter: _BoxPainter(layer: layer, open: open, leak: leak, glow: glow, tape: tape, label: label),
  );
}

const _kraft = Color(0xFFC8955A);
const _kraftSide = Color(0xFFA9773F);
const _kraftShade = Color(0xFF8E6131);
const _inside = Color(0xFF5A3A1C);
const _edge = Color(0xFF6B4520);

/// The box in its own space: x along its front (0 to [frontWidth]), y up
/// from the floor (0 to [height]), z into the screen (0 to [depth]), drawn
/// with an oblique projection.
class _Geometry {
  _Geometry(this.size)
    : shiftX = size.width * 0.2,
      shiftY = size.height * 0.18,
      frontWidth = size.width * 0.8,
      height = size.height * 0.82,
      depth = size.width * 0.45;

  final Size size;

  /// How far the back is drawn to the right of and above the front.
  final double shiftX;
  final double shiftY;
  final double frontWidth;
  final double height;
  final double depth;

  Offset at(double x, double y, double z) => Offset(x + z / depth * shiftX, size.height - y - z / depth * shiftY);

  /// A point of its open top.
  Offset top(double x, double z) => at(x, height, z);
}

class _BoxPainter extends CustomPainter {
  _BoxPainter({
    required this.layer,
    required this.open,
    required this.leak,
    required this.glow,
    required this.tape,
    required this.label,
  });

  final GachaBoxLayer layer;
  final double open;
  final double leak;
  final Color glow;
  final Color tape;
  final String label;

  /// The side flaps open first, the front and back ones after: each turns
  /// up and over, past upright; the front and back ones fall further, so the
  /// front one doesn't hide what comes out.
  double get _sideTurn => Curves.easeOutBack.transform(const Interval(0, 0.6).transform(open)) * (pi / 2 + 0.55);
  double get _endTurn => Curves.easeOutBack.transform(const Interval(0.3, 1).transform(open)) * pi * 0.86;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(size);
    switch (layer) {
      case GachaBoxLayer.back:
        _paintBack(canvas, g);
      case GachaBoxLayer.front:
        _paintFront(canvas, g);
    }
  }

  void _paintBack(Canvas canvas, _Geometry g) {
    final w = g.frontWidth;
    final d = g.depth;
    // Its shadow on the floor.
    canvas.drawOval(
      Rect.fromCenter(
        center: g.at(w / 2, 0, d / 2) + Offset(0, g.shiftY * 0.2),
        width: w * 1.5,
        height: g.shiftY * 1.6,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // The inside, dark towards the bottom.
    final opening = _polygon([g.top(0, 0), g.top(w, 0), g.top(w, d), g.top(0, d)]);
    canvas.drawPath(opening, Paint()..color = _inside);
    // Light pours out once it opens.
    if (open > 0 && leak > 0) {
      final center = g.top(w / 2, d / 2);
      final radius = w * (0.4 + 0.5 * open);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              glow.withValues(alpha: leak * open),
              glow.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    final endTurn = _endTurn;
    // The back flap, then the side ones on top of it, and the front one
    // while it's still shut (once it opens, it falls in front of the card).
    _flap(canvas, g, hinge: (Offset(0, d), Offset(w, d)), turn: endTurn, outward: const _Out(0, 1), length: d / 2);
    if (endTurn == 0) {
      _flap(canvas, g, hinge: (Offset.zero, Offset(w, 0)), turn: 0, outward: const _Out(0, -1), length: d / 2);
    }
    final sideTurn = _sideTurn;
    _flap(canvas, g, hinge: (Offset.zero, Offset(0, d)), turn: sideTurn, outward: const _Out(-1, 0), length: w / 2);
    _flap(canvas, g, hinge: (Offset(w, 0), Offset(w, d)), turn: sideTurn, outward: const _Out(1, 0), length: w / 2);
    // Taped shut down the middle, the tape tearing as it opens.
    final tapeLeft = 1 - const Interval(0, 0.2).transform(open);
    if (tapeLeft > 0) {
      final half = w * 0.08;
      canvas.drawPath(
        _polygon([g.top(w / 2 - half, 0), g.top(w / 2 + half, 0), g.top(w / 2 + half, d), g.top(w / 2 - half, d)]),
        Paint()..color = tape.withValues(alpha: 0.9 * tapeLeft),
      );
    }
    // Shut, it leaks light through its seams.
    if (open == 0 && leak > 0) {
      final seams = Path()
        ..moveTo(g.top(w / 2, 0).dx, g.top(w / 2, 0).dy)
        ..lineTo(g.top(w / 2, d).dx, g.top(w / 2, d).dy)
        ..addPath(_polygon([g.top(0, 0), g.top(w, 0), g.top(w, d), g.top(0, d)]), Offset.zero);
      canvas.drawPath(
        seams,
        Paint()
          ..color = glow.withValues(alpha: leak)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 + 10 * leak
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 8 * leak),
      );
      canvas.drawPath(
        seams,
        Paint()
          ..color = Color.lerp(glow, Colors.white, 0.6)!.withValues(alpha: leak)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _paintFront(Canvas canvas, _Geometry g) {
    final w = g.frontWidth;
    final d = g.depth;
    final h = g.height;
    final outline = Paint()
      ..color = _edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    // The right wall, in the shade.
    final side = _polygon([g.at(w, 0, 0), g.at(w, h, 0), g.at(w, h, d), g.at(w, 0, d)]);
    canvas.drawPath(side, Paint()..color = _kraftSide);
    // The front wall, lit from above.
    final frontRect = Rect.fromPoints(g.at(0, h, 0), g.at(w, 0, 0));
    final front = Path()..addRect(frontRect);
    canvas.drawPath(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kraft, _kraftShade],
          stops: [0.4, 1],
        ).createShader(frontRect),
    );
    // A carry handle cut into the side.
    final handle = g.at(w, h * 0.72, d / 2);
    canvas.drawPath(
      _polygon([
        handle + Offset(-g.shiftX * 0.3, g.shiftY * 0.28 - 4),
        handle + Offset(g.shiftX * 0.3, -g.shiftY * 0.28 - 4),
        handle + Offset(g.shiftX * 0.3, -g.shiftY * 0.28 + 4),
        handle + Offset(-g.shiftX * 0.3, g.shiftY * 0.28 + 4),
      ]),
      Paint()..color = _inside,
    );
    // The tape runs down the front too.
    final tapeLeft = 1 - const Interval(0, 0.2).transform(open);
    if (tapeLeft > 0) {
      final half = w * 0.08;
      canvas.drawRect(
        Rect.fromLTRB(w / 2 - half, frontRect.top, w / 2 + half, frontRect.top + h * 0.28),
        Paint()..color = tape.withValues(alpha: 0.9 * tapeLeft),
      );
    }
    _stamp(canvas, frontRect);
    // Sketchy outlines: each line drawn twice, a little off.
    for (final path in [side, front]) {
      canvas.drawPath(path, outline);
      canvas.drawPath(
        path.shift(const Offset(1.2, -0.8)),
        Paint()
          ..color = _edge.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    // The front flap falls forward over the front wall once it opens.
    final endTurn = _endTurn;
    if (endTurn > 0) {
      _flap(canvas, g, hinge: (Offset.zero, Offset(w, 0)), turn: endTurn, outward: const _Out(0, -1), length: d / 2);
    }
  }

  /// "DRAWING DUEL" stamped on the front, a little askew.
  void _stamp(Canvas canvas, Rect front) {
    final ink = _edge.withValues(alpha: 0.75);
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: ink,
          fontSize: front.width * 0.09,
          fontWeight: FontWeight.w900,
          letterSpacing: front.width * 0.008,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: front.width * 0.8);
    final center = front.center + Offset(0, front.height * 0.12);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.07);
    final badge = Rect.fromCenter(center: Offset.zero, width: text.width + 20, height: text.height + 34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badge, const Radius.circular(6)),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final brush = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.brush_rounded.codePoint),
        style: TextStyle(fontFamily: Icons.brush_rounded.fontFamily, fontSize: 14, color: ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    brush.paint(canvas, Offset(-brush.width / 2, badge.top + 3));
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2 + 6));
    canvas.restore();
  }

  /// A flap along [hinge] (two points of the top, as x and z), [length]
  /// long, turned up by [turn] from lying flat across the top, towards
  /// [outward] past upright.
  void _flap(
    Canvas canvas,
    _Geometry g, {
    required (Offset, Offset) hinge,
    required double turn,
    required _Out outward,
    required double length,
  }) {
    final (a, b) = hinge;
    // Flat, it lies across the top, away from [outward]; turned, it rises
    // and falls outward.
    final across = -cos(turn) * length;
    final up = sin(turn) * length;
    Offset far(Offset p) => g.at(p.dx + outward.x * across, g.height + up, p.dy + outward.z * across);
    final flap = _polygon([g.top(a.dx, a.dy), g.top(b.dx, b.dy), far(b), far(a)]);
    // Lit flat on top, darker the more it stands up and turns away.
    canvas.drawPath(flap, Paint()..color = Color.lerp(_kraft, _kraftSide, (sin(turn) * 0.8).clamp(0, 1))!);
    canvas.drawPath(
      flap,
      Paint()
        ..color = _edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.layer != layer ||
      old.open != open ||
      old.leak != leak ||
      old.glow != glow ||
      old.tape != tape ||
      old.label != label;
}

/// Which way a flap falls once open: along x or z.
class _Out {
  const _Out(this.x, this.z);

  final double x;
  final double z;
}
