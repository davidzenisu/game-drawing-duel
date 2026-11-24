import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A point or direction in the box's space: x to the right, y down, z away
/// from you, with the box standing around the origin.
typedef BoxPoint = ({double x, double y, double z});

/// The camera looking at a [GachaBox]: turned round it by [yaw], looking
/// down on it by [pitch], tilted by [roll], [zoom]ed in and the picture
/// [shift]ed, all in perspective.
class BoxCamera {
  const BoxCamera({this.yaw = -0.5, this.pitch = 0.6, this.roll = 0, this.zoom = 1, this.shift = Offset.zero});

  final double yaw;
  final double pitch;
  final double roll;
  final double zoom;
  final Offset shift;

  /// How far the eye is from the box, in its units.
  static const distance = 720.0;

  /// [p] turned to face the camera, the camera looking along z.
  BoxPoint turn(BoxPoint p) {
    final (cy, sy) = (cos(yaw), sin(yaw));
    final x1 = p.x * cy + p.z * sy;
    final z1 = -p.x * sy + p.z * cy;
    final (cp, sp) = (cos(pitch), sin(pitch));
    return (x: x1, y: p.y * cp - z1 * sp, z: p.y * sp + z1 * cp);
  }

  /// How much bigger than its size [p] shows, the nearer the bigger.
  double scaleAt(BoxPoint p) => zoom * distance / (distance + turn(p).z);

  /// Where [p] shows, from the middle of the picture.
  Offset project(BoxPoint p) {
    final t = turn(p);
    final s = zoom * distance / (distance + t.z);
    final (cr, sr) = (cos(roll), sin(roll));
    return Offset((t.x * cr - t.y * sr) * s, (t.x * sr + t.y * cr) * s) + shift;
  }

  /// Whether a face at [center] with [normal] (pointing out of its visible
  /// side) faces the camera.
  bool faces(BoxPoint center, BoxPoint normal) {
    final c = turn(center);
    final n = turn(normal);
    return n.x * c.x + n.y * c.y + n.z * (c.z + distance) < 0;
  }

  /// How far [p] is from the camera, to draw the far things first.
  double depth(BoxPoint p) => turn(p).z;

  static BoxCamera lerp(BoxCamera a, BoxCamera b, double t) => BoxCamera(
    yaw: a.yaw + (b.yaw - a.yaw) * t,
    pitch: a.pitch + (b.pitch - a.pitch) * t,
    roll: a.roll + (b.roll - a.roll) * t,
    zoom: a.zoom + (b.zoom - a.zoom) * t,
    shift: Offset.lerp(a.shift, b.shift, t)!,
  );

  BoxCamera copyWith({double? yaw, double? pitch, double? roll, double? zoom, Offset? shift}) => BoxCamera(
    yaw: yaw ?? this.yaw,
    pitch: pitch ?? this.pitch,
    roll: roll ?? this.roll,
    zoom: zoom ?? this.zoom,
    shift: shift ?? this.shift,
  );
}

/// The two halves of a [GachaBox], so cards can be drawn coming out of it:
/// the [back] (its inside and its flaps) under the cards, the [front] (its
/// outer walls and, once open, the front flap) over them.
enum GachaBoxLayer { back, front }

/// The cardboard box pulls come out of, in 3D, as [camera] sees it from the
/// middle of the space it fills. Taped shut along the seam of its two top
/// flaps, the tape is [cut] from left to right, the cut and then the seams
/// leaking [leak] of [glow]'s light; its flaps then fold [open] and the
/// light pours out.
class GachaBox extends StatelessWidget {
  const GachaBox({
    super.key,
    required this.camera,
    required this.layer,
    this.cut = 0,
    this.open = 0,
    this.leak = 0,
    this.glow = Colors.white,
    this.tape = GachaBox.plainTape,
    this.label = 'DRAWING DUEL',
  });

  /// Its width (left to right), height and depth.
  static const width = 240.0;
  static const height = 170.0;
  static const depth = 170.0;

  static const plainTape = Color(0xFFE6D3A8);

  /// The Arena banner's tape: red, like its banner.
  static const arenaTape = Color(0xFFD8402F);

  /// Where a point [below] the top of its opening, in its middle, shows:
  /// where cards come out.
  static Offset inside(BoxCamera camera, {double below = 0}) => camera.project((x: 0, y: -height / 2 + below, z: 0));

  /// Where the tape is cut up to, for a [cut] from 0 (its left end) to 1.
  static Offset cutAt(BoxCamera camera, double cut) =>
      camera.project((x: -width / 2 + width * cut, y: -height / 2 - 1, z: 0));

  /// How long the tape shows across the top.
  static double tapeLength(BoxCamera camera) => (cutAt(camera, 1) - cutAt(camera, 0)).distance;

  final BoxCamera camera;
  final GachaBoxLayer layer;
  final double cut;
  final double open;
  final double leak;
  final Color glow;
  final Color tape;
  final String label;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BoxPainter(
      camera: camera,
      layer: layer,
      cut: cut,
      open: open,
      leak: leak,
      glow: glow,
      tape: tape,
      label: label,
    ),
    child: const SizedBox.expand(),
  );
}

const _kraft = Color(0xFFC8955A);
const _kraftDark = Color(0xFF5E3D1C);
const _inside = Color(0xFF9C7446);
const _insideDark = Color(0xFF3A2410);
const _edge = Color(0xFF5A3816);

/// Towards the light: above, to the left and in front.
final BoxPoint _light = _normalize((x: -0.45, y: -1, z: -0.7));

BoxPoint _normalize(BoxPoint v) {
  final l = sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  return (x: v.x / l, y: v.y / l, z: v.z / l);
}

BoxPoint _add(BoxPoint a, BoxPoint b) => (x: a.x + b.x, y: a.y + b.y, z: a.z + b.z);
BoxPoint _scale(BoxPoint a, double s) => (x: a.x * s, y: a.y * s, z: a.z * s);
BoxPoint _neg(BoxPoint a) => _scale(a, -1);
double _dot(BoxPoint a, BoxPoint b) => a.x * b.x + a.y * b.y + a.z * b.z;
BoxPoint _mid(List<BoxPoint> ps) => _scale(ps.reduce(_add), 1 / ps.length);

/// [base] lit from [_light] on a face turned to [normal].
Color _lit(Color base, Color shade, BoxPoint normal) =>
    Color.lerp(shade, base, 0.35 + 0.65 * max(0, _dot(normal, _light)))!;

/// A flat face: its corners in order and which way it faces.
class _Face {
  const _Face(this.corners, this.normal, {this.name = ''});

  final List<BoxPoint> corners;
  final BoxPoint normal;
  final String name;

  BoxPoint get center => _mid(corners);
}

class _BoxPainter extends CustomPainter {
  _BoxPainter({
    required this.camera,
    required this.layer,
    required this.cut,
    required this.open,
    required this.leak,
    required this.glow,
    required this.tape,
    required this.label,
  });

  final BoxCamera camera;
  final GachaBoxLayer layer;
  final double cut;
  final double open;
  final double leak;
  final Color glow;
  final Color tape;
  final String label;

  static const _w = GachaBox.width / 2;
  static const _h = GachaBox.height / 2;
  static const _d = GachaBox.depth / 2;

  /// Half the tape's width.
  static const _tape = 13.0;

  static const _up = (x: 0.0, y: -1.0, z: 0.0);

  /// The top flaps (front and back, meeting under the tape) open first,
  /// the side ones after; each turns up and over, past upright.
  double get _topTurn => Curves.easeOutBack.transform(const Interval(0, 0.65).transform(open)) * pi * 0.82;
  double get _sideTurn => Curves.easeOutBack.transform(const Interval(0.3, 1).transform(open)) * (pi / 2 + 0.5);

  late Offset _center;

  Offset _p(BoxPoint p) => _center + camera.project(p);

  Path _path(List<BoxPoint> corners) => Path()..addPolygon([for (final c in corners) _p(c)], true);

  /// The walls, facing out.
  static const _walls = [
    _Face(
      [(x: -_w, y: -_h, z: -_d), (x: _w, y: -_h, z: -_d), (x: _w, y: _h, z: -_d), (x: -_w, y: _h, z: -_d)],
      (x: 0.0, y: 0.0, z: -1.0),
      name: 'front',
    ),
    _Face(
      [(x: _w, y: -_h, z: _d), (x: -_w, y: -_h, z: _d), (x: -_w, y: _h, z: _d), (x: _w, y: _h, z: _d)],
      (x: 0.0, y: 0.0, z: 1.0),
      name: 'back',
    ),
    _Face(
      [(x: -_w, y: -_h, z: _d), (x: -_w, y: -_h, z: -_d), (x: -_w, y: _h, z: -_d), (x: -_w, y: _h, z: _d)],
      (x: -1.0, y: 0.0, z: 0.0),
      name: 'left',
    ),
    _Face(
      [(x: _w, y: -_h, z: -_d), (x: _w, y: -_h, z: _d), (x: _w, y: _h, z: _d), (x: _w, y: _h, z: -_d)],
      (x: 1.0, y: 0.0, z: 0.0),
      name: 'right',
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _center = size.center(Offset.zero);
    switch (layer) {
      case GachaBoxLayer.back:
        _paintBack(canvas);
      case GachaBoxLayer.front:
        _paintFront(canvas);
    }
  }

  void _paintBack(Canvas canvas) {
    // Its shadow on the floor, cast away from the light.
    final floor = [(x: -_w, y: _h, z: -_d), (x: _w, y: _h, z: -_d), (x: _w, y: _h, z: _d), (x: -_w, y: _h, z: _d)];
    canvas.drawPath(
      _path([for (final c in floor) _add(c, (x: c.x * 0.15 + 18, y: 0, z: c.z * 0.15 + 22))]),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * camera.zoom),
    );
    // The inside: the floor and the far walls, seen through the top.
    final inner =
        [
            _Face([...floor.reversed], _up),
            for (final wall in _walls) _Face([...wall.corners.reversed], _neg(wall.normal)),
          ].where((f) => camera.faces(f.center, f.normal)).toList()
          ..sort((a, b) => camera.depth(b.center).compareTo(camera.depth(a.center)));
    for (final face in inner) {
      final path = _path(face.corners);
      // Darker the deeper down.
      canvas.drawPath(path, Paint()..color = _lit(_inside, _insideDark, face.normal));
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, _insideDark.withValues(alpha: 0.7)],
          ).createShader(path.getBounds()),
      );
    }
    final sideTurn = _sideTurn;
    final topTurn = _topTurn;
    // The side flaps under the top ones, then the back top flap, and the
    // front one while still shut (once it opens, it falls in front of the
    // cards).
    _flap(
      canvas,
      hinge: ((x: -_w, y: -_h, z: _d), (x: -_w, y: -_h, z: -_d)),
      inward: (x: 1, y: 0, z: 0),
      length: _w * 0.9,
      turn: sideTurn,
    );
    _flap(
      canvas,
      hinge: ((x: _w, y: -_h, z: -_d), (x: _w, y: -_h, z: _d)),
      inward: (x: -1, y: 0, z: 0),
      length: _w * 0.9,
      turn: sideTurn,
    );
    _flap(
      canvas,
      hinge: ((x: _w, y: -_h, z: _d), (x: -_w, y: -_h, z: _d)),
      inward: (x: 0, y: 0, z: -1),
      length: _d,
      turn: topTurn,
      taped: true,
    );
    if (topTurn == 0) {
      _flap(
        canvas,
        hinge: ((x: -_w, y: -_h, z: -_d), (x: _w, y: -_h, z: -_d)),
        inward: (x: 0, y: 0, z: 1),
        length: _d,
        turn: 0,
        taped: true,
      );
    }
    if (open == 0) {
      _paintCut(canvas);
    } else if (leak > 0) {
      _paintBeam(canvas);
    }
  }

  /// The cut along the tape, and once it's through the seams, glowing.
  void _paintCut(Canvas canvas) {
    if (leak <= 0) return;
    final seam = Path();
    final from = _p((x: -_w, y: -_h - 0.5, z: 0));
    final to = _p((x: -_w + 2 * _w * cut, y: -_h - 0.5, z: 0));
    seam
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
    if (cut >= 1) {
      // Light leaks round the flaps too.
      seam.addPath(
        _path([(x: -_w, y: -_h, z: -_d), (x: _w, y: -_h, z: -_d), (x: _w, y: -_h, z: _d), (x: -_w, y: -_h, z: _d)]),
        Offset.zero,
      );
    }
    final z = camera.zoom;
    // Light shining out of the cut: a wide soft bloom on the tape round
    // it, a brighter haze, and a thin white-hot line, brighter the further
    // the cut; no hard edges.
    final bright = 0.5 + 0.5 * leak;
    for (final (width, blur, alpha, color) in [
      (34.0, 18.0, 0.35, glow),
      (16.0, 8.0, 0.6, glow),
      (6.0, 3.0, 0.9, Color.lerp(glow, Colors.white, 0.6)!),
    ]) {
      canvas.drawPath(
        seam,
        Paint()
          ..blendMode = BlendMode.screen
          ..color = color.withValues(alpha: alpha * bright)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * (0.6 + 0.4 * leak) * z
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * z),
      );
    }
    canvas.drawPath(
      seam,
      Paint()
        ..color = Colors.white.withValues(alpha: bright)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * z
        ..strokeCap = StrokeCap.round,
    );
    // Where the blade is, the light flares.
    if (cut > 0 && cut < 1) _flare(canvas, to, 30 * z * bright);
  }

  /// A star of light at [at], [size] across its glow, with long thin rays.
  void _flare(Canvas canvas, Offset at, double size) {
    canvas.drawCircle(
      at,
      size,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [Colors.white, glow.withValues(alpha: 0.6), glow.withValues(alpha: 0)],
          stops: const [0, 0.35, 1],
        ).createShader(Rect.fromCircle(center: at, radius: size)),
    );
    final ray = Paint()
      ..blendMode = BlendMode.screen
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.06);
    for (final (angle, length) in [(0.0, 2.2), (pi / 2, 1.3), (pi / 4, 0.8), (-pi / 4, 0.8)]) {
      final reach = Offset(cos(angle), sin(angle)) * size * length;
      ray
        ..strokeWidth = size * 0.09
        ..shader = ui.Gradient.linear(
          at - reach,
          at + reach,
          [glow.withValues(alpha: 0), Colors.white.withValues(alpha: 0.9), glow.withValues(alpha: 0)],
          const [0, 0.5, 1],
        );
      canvas.drawLine(at - reach, at + reach, ray);
    }
  }

  /// Light pouring up out of the open box.
  void _paintBeam(Canvas canvas) {
    final strength = leak * Curves.easeOut.transform(min(1, open * 2));
    final rim = [(x: -_w, y: -_h, z: -_d), (x: _w, y: -_h, z: -_d), (x: _w, y: -_h, z: _d), (x: -_w, y: -_h, z: _d)];
    final rise = 260.0 * strength;
    final top = [for (final c in rim) (x: c.x * 1.5, y: c.y - rise, z: c.z * 1.5)];
    final bottomAt = _p((x: 0, y: -_h, z: 0));
    final topAt = _p((x: 0, y: -_h - rise, z: 0));
    final beam = Paint()
      ..blendMode = BlendMode.screen
      ..shader = ui.Gradient.linear(bottomAt, topAt == bottomAt ? bottomAt + const Offset(0, -1) : topAt, [
        glow.withValues(alpha: 0.85 * strength),
        glow.withValues(alpha: 0),
      ])
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * camera.zoom);
    // Each side of the beam, from the rim up and out.
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      canvas.drawPath(_path([rim[i], rim[j], top[j], top[i]]), beam);
    }
    final glowAt = _p((x: 0, y: -_h - 20, z: 0));
    final radius = GachaBox.width * 0.8 * camera.zoom;
    canvas.drawCircle(
      glowAt,
      radius,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [
            Color.lerp(glow, Colors.white, 0.5)!.withValues(alpha: strength),
            glow.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: glowAt, radius: radius)),
    );
  }

  void _paintFront(Canvas canvas) {
    final walls = _walls.where((f) => camera.faces(f.center, f.normal)).toList()
      ..sort((a, b) => camera.depth(b.center).compareTo(camera.depth(a.center)));
    final outline = Paint()
      ..color = _edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * camera.zoom
      ..strokeJoin = StrokeJoin.round;
    for (final wall in walls) {
      final path = _path(wall.corners);
      final rect = path.getBounds();
      canvas.drawPath(path, Paint()..color = _lit(_kraft, _kraftDark, wall.normal));
      // A little darker towards the floor.
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.08), Colors.black.withValues(alpha: 0.18)],
          ).createShader(rect),
      );
      _onFace(canvas, wall, (canvas, size) {
        if (wall.name == 'front') {
          _stamp(canvas, size);
        } else {
          _sideDetails(canvas, size);
        }
        // The corrugated edge along the top.
        canvas.drawLine(
          const Offset(0, 3),
          Offset(size.width, 3),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.18)
            ..strokeWidth = 2,
        );
      });
      canvas.drawPath(path, outline);
    }
    final topTurn = _topTurn;
    if (topTurn > 0) {
      _flap(
        canvas,
        hinge: ((x: -_w, y: -_h, z: -_d), (x: _w, y: -_h, z: -_d)),
        inward: (x: 0, y: 0, z: 1),
        length: _d,
        turn: topTurn,
        taped: true,
      );
    }
  }

  /// Draws on [face] as if it were a flat [Size] of its own, its top left
  /// at its first corner.
  void _onFace(Canvas canvas, _Face face, void Function(Canvas canvas, Size size) draw) {
    final [a, b, _, d] = face.corners;
    final size = Size(
      sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2) + pow(b.z - a.z, 2)),
      sqrt(pow(d.x - a.x, 2) + pow(d.y - a.y, 2) + pow(d.z - a.z, 2)),
    );
    final (pa, pb, pd) = (_p(a), _p(b), _p(d));
    final across = (pb - pa) / size.width;
    final down = (pd - pa) / size.height;
    canvas.save();
    canvas.clipPath(_path(face.corners));
    canvas.transform(
      Matrix4(across.dx, across.dy, 0, 0, down.dx, down.dy, 0, 0, 0, 0, 1, 0, pa.dx, pa.dy, 0, 1).storage,
    );
    draw(canvas, size);
    canvas.restore();
  }

  /// "DRAWING DUEL" stamped on the front, a little askew.
  void _stamp(Canvas canvas, Size size) {
    final ink = _edge.withValues(alpha: 0.75);
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 2),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.8);
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.56);
    canvas.rotate(-0.07);
    final badge = Rect.fromCenter(center: Offset.zero, width: text.width + 24, height: text.height + 36);
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
        style: TextStyle(fontFamily: Icons.brush_rounded.fontFamily, fontSize: 16, color: ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    brush.paint(canvas, Offset(-brush.width / 2, badge.top + 3));
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2 + 7));
    canvas.restore();
    // "This side up" arrows in a corner.
    final arrows = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final x in [size.width - 34, size.width - 22]) {
      canvas.drawLine(Offset(x, 34), Offset(x, 18), arrows);
      canvas.drawPath(
        Path()
          ..moveTo(x - 4, 23)
          ..lineTo(x, 18)
          ..lineTo(x + 4, 23),
        arrows,
      );
    }
  }

  /// A side wall's carry handle and the tape's end running down it.
  void _sideDetails(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.28), width: size.width * 0.38, height: 13),
        const Radius.circular(7),
      ),
      Paint()..color = _insideDark,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width / 2 - _tape, 0, 2 * _tape, size.height * 0.16),
      Paint()..color = tape.withValues(alpha: 0.92),
    );
  }

  /// A flap along [hinge], [length] long, lying flat across the top towards
  /// [inward] when shut and turned up and over by [turn]. The top ones
  /// carry half of the tape each, at their edge.
  void _flap(
    Canvas canvas, {
    required (BoxPoint, BoxPoint) hinge,
    required BoxPoint inward,
    required double length,
    required double turn,
    bool taped = false,
  }) {
    final (a, b) = hinge;
    final along = _add(_scale(inward, cos(turn)), _scale(_up, sin(turn)));
    BoxPoint at(BoxPoint p, double reach) => _add(p, _scale(along, reach));
    final corners = [a, b, at(b, length), at(a, length)];
    // The outside faces up when shut, then turns away.
    final outside = _add(_scale(inward, -sin(turn)), _scale(_up, cos(turn)));
    final center = _mid(corners);
    final showsOutside = camera.faces(center, outside);
    final path = _path(corners);
    canvas.drawPath(
      path,
      Paint()..color = showsOutside ? _lit(_kraft, _kraftDark, outside) : _lit(_inside, _insideDark, _neg(outside)),
    );
    if (taped && showsOutside) {
      canvas.drawPath(
        _path([at(a, length - _tape), at(b, length - _tape), at(b, length), at(a, length)]),
        Paint()..color = Color.lerp(tape, Colors.white, 0.15 * max(0, _dot(outside, _light)))!.withValues(alpha: 0.95),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * camera.zoom
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.camera != camera ||
      old.layer != layer ||
      old.cut != cut ||
      old.open != open ||
      old.leak != leak ||
      old.glow != glow ||
      old.tape != tape ||
      old.label != label;
}
