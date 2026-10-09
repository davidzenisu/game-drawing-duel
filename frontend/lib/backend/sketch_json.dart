import 'dart:ui';

import '../game/rules/models.dart';

/// The JSON form of a [Sketch] the API stores, see `SketchData` in the backend:
/// `{"strokes": [{"color": 0xFF000000, "width": 0.016, "points": [x, y, …]}]}`.
abstract final class SketchJson {
  static Map<String, Object?> encode(Sketch sketch) => {
    'strokes': [
      for (final stroke in sketch.strokes)
        {
          'color': stroke.color.toARGB32(),
          'width': _round(stroke.width),
          'points': [
            for (final point in stroke.points) ...[_round(point.dx), _round(point.dy)],
          ],
        },
    ],
  };

  static Sketch decode(Object? json) {
    if (json case {'strokes': List strokes}) {
      return Sketch([
        for (final stroke in strokes)
          if (stroke case {'color': int color, 'width': num width, 'points': List points})
            Stroke(
              color: Color(color),
              width: width.toDouble(),
              points: [
                for (var i = 0; i + 1 < points.length; i += 2)
                  Offset((points[i] as num).toDouble(), (points[i + 1] as num).toDouble()),
              ],
            )
          else
            throw const FormatException('Unexpected stroke in sketch.'),
      ]);
    }
    throw const FormatException('Unexpected sketch.');
  }

  /// A ten-thousandth of the canvas is finer than any screen shows, and
  /// keeps the files small.
  static double _round(double value) => (value * 10000).roundToDouble() / 10000;
}
