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
class SketchPad extends StatelessWidget {
  const SketchPad({super.key, required this.controller});

  final SketchPadController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        Offset normalise(Offset local) =>
            Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => controller._begin(normalise(details.localPosition)),
          onPanUpdate: (details) => controller._extend(normalise(details.localPosition)),
          child: CustomPaint(
            painter: SketchPainter(controller.strokes, repaint: controller),
            size: size,
          ),
        );
      },
    );
  }
}
