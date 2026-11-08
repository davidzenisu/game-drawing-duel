import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/models.dart';

/// Width to height ratio of every character card.
const cardAspectRatio = 4 / 5;

/// Brush sizes relative to the canvas width.
const brushWidths = [0.008, 0.016, 0.035];

class SketchPainter extends CustomPainter {
  SketchPainter(this.strokes, {super.repaint});

  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final points = [for (final p in stroke.points) Offset(p.dx * size.width, p.dy * size.height)];
      if (points.length == 1) {
        canvas.drawCircle(points.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length - 1; i++) {
        final mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
        path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(SketchPainter oldDelegate) => oldDelegate.strokes != strokes;
}

/// Read-only rendering of a [Sketch].
class SketchView extends StatelessWidget {
  const SketchView(this.sketch, {super.key});

  final Sketch sketch;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: SketchPainter(sketch.strokes), size: Size.infinite),
    );
  }
}

class SketchPadController extends ChangeNotifier {
  final List<Stroke> _strokes = [];
  Color color = AppPalette.ink;
  double width = brushWidths[1];
  bool enabled = true;

  List<Stroke> get strokes => _strokes;

  bool get isEmpty => _strokes.isEmpty;

  Sketch toSketch() =>
      Sketch([for (final s in _strokes) Stroke(color: s.color, width: s.width, points: List.unmodifiable(s.points))]);

  void setColor(Color value) {
    color = value;
    notifyListeners();
  }

  void setWidth(double value) {
    width = value;
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  void lock() {
    enabled = false;
    notifyListeners();
  }

  void _begin(Offset point) {
    if (!enabled) return;
    _strokes.add(Stroke(color: color, width: width, points: [point]));
    notifyListeners();
  }

  void _extend(Offset point) {
    if (!enabled || _strokes.isEmpty) return;
    _strokes.last.points.add(point);
    notifyListeners();
  }
}

/// Editable drawing surface. Points are stored normalised to its size.
///
/// A touch that lands on it is its own at once, so nothing else claims the
/// gesture: e.g. the app-wide text selection would otherwise take a quick
/// tap (on a brush) then drag (on the canvas) for selecting text.
class SketchPad extends StatefulWidget {
  const SketchPad({super.key, required this.controller});

  final SketchPadController controller;

  @override
  State<SketchPad> createState() => _SketchPadState();
}

class _SketchPadState extends State<SketchPad> {
  /// The pointer drawing, and where it went down until it first moves; one
  /// finger draws at a time.
  int? _pointer;
  Offset? _down;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        Offset normalise(Offset local) =>
            Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));
        return SelectionContainer.disabled(
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (_) {},
              ),
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (_pointer != null) return;
                _pointer = event.pointer;
                _down = event.localPosition;
              },
              onPointerMove: (event) {
                if (event.pointer != _pointer) return;
                // A stroke starts where the finger went down, once it moves.
                if (_down case final down?) {
                  widget.controller._begin(normalise(down));
                  _down = null;
                }
                widget.controller._extend(normalise(event.localPosition));
              },
              onPointerUp: (event) => _release(event.pointer),
              onPointerCancel: (event) => _release(event.pointer),
              child: CustomPaint(
                painter: SketchPainter(widget.controller.strokes, repaint: widget.controller),
                size: size,
              ),
            ),
          ),
        );
      },
    );
  }

  void _release(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    _down = null;
  }
}
