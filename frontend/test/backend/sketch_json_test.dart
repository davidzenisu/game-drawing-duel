import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/backend/sketch_json.dart';
import 'package:frontend/game/rules/models.dart';

void main() {
  const sketch = Sketch([
    Stroke(color: Color(0xFF000000), width: 0.016, points: [Offset(0.1, 0.2), Offset(0.123456, 1)]),
    Stroke(color: Color(0x80E53935), width: 0.035, points: [Offset(0.5, 0.5)]),
  ]);

  test('sketches are sent as flat, rounded point lists', () {
    expect(SketchJson.encode(sketch), {
      'strokes': [
        {
          'color': 0xFF000000,
          'width': 0.016,
          'points': [0.1, 0.2, 0.1235, 1.0],
        },
        {
          'color': 0x80E53935,
          'width': 0.035,
          'points': [0.5, 0.5],
        },
      ],
    });
  });

  test('sketches survive the round trip', () {
    final decoded = SketchJson.decode(SketchJson.encode(sketch));
    expect(decoded.strokes, hasLength(2));
    expect(decoded.strokes[0].color, const Color(0xFF000000));
    expect(decoded.strokes[0].points, [const Offset(0.1, 0.2), const Offset(0.1235, 1)]);
    expect(decoded.strokes[1].color, const Color(0x80E53935));
    expect(decoded.strokes[1].width, 0.035);
  });

  test('unexpected JSON is rejected', () {
    expect(() => SketchJson.decode({'strokes': 'nope'}), throwsFormatException);
    expect(
      () => SketchJson.decode({
        'strokes': [
          {'color': 'black'},
        ],
      }),
      throwsFormatException,
    );
  });
}
