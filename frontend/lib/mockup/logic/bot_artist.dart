import 'dart:math';
import 'dart:ui';

import '../../theme/palette.dart';
import 'models.dart';

/// Generates crude doodles for the simulated players of the mockup.
class BotArtist {
  BotArtist(int seed) : _random = Random(seed);

  final Random _random;

  static const titles = [
    'The early years',
    'Night Shift',
    'Monday morning',
    'On vacation',
    'After the gym',
    'Birthday edition',
    'Lost in IKEA',
    'Final boss',
    'Coffee first',
    'Unbothered',
    'Karaoke night',
    'The intern',
    'Out of office',
    'Wedding guest',
    'Sunday chef',
    'Overslept',
  ];

  String title() => titles[_random.nextInt(titles.length)];

  /// A stick figure with an accessory that hints at [prompt].
  Sketch doodle(String prompt) {
    final strokes = <Stroke>[];
    final ink = AppPalette.ink;
    final accent = AppPalette.brushes[1 + _random.nextInt(AppPalette.brushes.length - 1)];
    final cx = 0.5 + _jitter(0.05);
    final headY = 0.3 + _jitter(0.03);
    final headR = 0.12 + _jitter(0.02);

    strokes.add(_line(_ellipse(Offset(cx, headY), headR, headR * 1.1), ink));
    for (final side in [-1, 1]) {
      final eye = Offset(cx + side * headR * 0.4, headY - headR * 0.15);
      strokes.add(_line(_ellipse(eye, 0.015, 0.02, segments: 8), ink));
    }
    final smile = _random.nextBool();
    strokes.add(_line(_arc(Offset(cx, headY + headR * 0.35), headR * 0.45, smile), ink));

    final neck = Offset(cx, headY + headR * 1.1);
    final hip = Offset(cx + _jitter(0.03), 0.72);
    strokes.add(_line(_wobbly(neck, hip), ink));
    final shoulder = Offset.lerp(neck, hip, 0.2)!;
    final leftHand = Offset(cx - 0.2 + _jitter(0.04), 0.55 + _jitter(0.1));
    final rightHand = Offset(cx + 0.2 + _jitter(0.04), 0.55 + _jitter(0.1));
    strokes.add(_line(_wobbly(shoulder, leftHand), ink));
    strokes.add(_line(_wobbly(shoulder, rightHand), ink));
    strokes.add(_line(_wobbly(hip, Offset(cx - 0.12 + _jitter(0.03), 0.93)), ink));
    strokes.add(_line(_wobbly(hip, Offset(cx + 0.12 + _jitter(0.03), 0.93)), ink));

    final top = Offset(cx, headY - headR * 1.1);
    final p = prompt.toLowerCase();
    if (p.contains('knight')) {
      strokes.add(_line(_wobbly(rightHand, rightHand + const Offset(0.08, -0.3)), accent, width: 0.02));
      strokes.add(_line(_wobbly(rightHand + const Offset(-0.05, -0.03), rightHand + const Offset(0.06, 0.02)), accent));
      strokes.add(_line(_ellipse(leftHand, 0.07, 0.09), accent));
    } else if (p.contains('mage')) {
      strokes.add(
        _line([
          top + Offset(-headR * 1.2, 0.01),
          top + const Offset(0.02, -0.2),
          top + Offset(headR * 1.2, 0.01),
        ], accent),
      );
      strokes.add(
        _line(_wobbly(leftHand + const Offset(0, -0.2), leftHand + const Offset(0, 0.2)), accent, width: 0.015),
      );
      strokes.add(_line(_star(leftHand + const Offset(0, -0.23), 0.04), AppPalette.brushes[3]));
    } else if (p.contains('rogue')) {
      strokes.add(
        _line(
          _wobbly(Offset(cx - headR, headY - headR * 0.15), Offset(cx + headR, headY - headR * 0.15)),
          accent,
          width: 0.03,
        ),
      );
      strokes.add(_line(_wobbly(rightHand, rightHand + const Offset(0.06, -0.1)), ink, width: 0.012));
    } else if (p.contains('legend')) {
      strokes.add(
        _line(
          [
            top + Offset(-headR, 0.02),
            top + Offset(-headR * 0.8, -0.08),
            top + Offset(-headR * 0.3, -0.02),
            top + const Offset(0, -0.1),
            top + Offset(headR * 0.3, -0.02),
            top + Offset(headR * 0.8, -0.08),
            top + Offset(headR, 0.02),
            top + Offset(-headR, 0.02),
          ],
          AppPalette.rarityLegend,
          width: 0.015,
        ),
      );
      strokes.add(_line(_wobbly(shoulder, Offset(cx - 0.25, 0.9)), accent));
      strokes.add(_line(_wobbly(shoulder, Offset(cx + 0.25, 0.9)), accent));
    } else if (p.contains('alter')) {
      strokes.add(_line(_scribble(top, headR * 1.2), accent));
    } else if (p.contains('challenger')) {
      for (var i = -2; i <= 2; i++) {
        strokes.add(_line(_wobbly(top + Offset(i * headR * 0.35, 0.02), top + Offset(i * headR * 0.5, -0.08)), accent));
      }
      strokes.add(_line(_wobbly(leftHand, leftHand + const Offset(-0.05, -0.08)), accent, width: 0.02));
      strokes.add(_line(_wobbly(rightHand, rightHand + const Offset(0.05, -0.08)), accent, width: 0.02));
    } else {
      strokes.add(_line(_scribble(top, headR), ink));
    }
    return Sketch(strokes);
  }

  double _jitter(double amount) => (_random.nextDouble() * 2 - 1) * amount;

  Stroke _line(List<Offset> points, Color color, {double width = 0.01}) =>
      Stroke(color: color, width: width, points: points);

  List<Offset> _wobbly(Offset from, Offset to, {int segments = 6}) => [
    for (var i = 0; i <= segments; i++)
      Offset.lerp(from, to, i / segments)! +
          (i == 0 || i == segments ? Offset.zero : Offset(_jitter(0.008), _jitter(0.008))),
  ];

  List<Offset> _ellipse(Offset center, double rx, double ry, {int segments = 20}) {
    final start = _random.nextDouble() * pi * 2;
    return [
      for (var i = 0; i <= segments + 1; i++)
        center +
            Offset(cos(start + i * 2 * pi / segments) * rx, sin(start + i * 2 * pi / segments) * ry) +
            Offset(_jitter(0.004), _jitter(0.004)),
    ];
  }

  List<Offset> _arc(Offset center, double radius, bool smile) => [
    for (var i = 0; i <= 8; i++)
      center +
          Offset(
            cos(pi * (0.15 + 0.7 * i / 8)) * radius,
            (smile ? 1 : -1) * sin(pi * (0.15 + 0.7 * i / 8)) * radius * 0.4,
          ),
  ];

  List<Offset> _star(Offset center, double radius) => [
    for (var i = 0; i <= 10; i++)
      center + Offset.fromDirection(-pi / 2 + i * pi / 5, i.isEven ? radius : radius * 0.45),
  ];

  List<Offset> _scribble(Offset center, double width) => [
    for (var i = 0; i < 24; i++) center + Offset(_jitter(width), _jitter(0.04) - 0.02),
  ];
}
