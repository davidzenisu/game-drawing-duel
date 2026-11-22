import 'dart:typed_data';
import 'dart:ui' as ui;

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

/// [sketch] as a PNG image on its cardboard card, [width] pixels wide, drawn
/// exactly like [SketchView] draws it, e.g. to download it.
Future<Uint8List> sketchPng(Sketch sketch, {int width = 800}) async {
  final size = Size(width.toDouble(), (width / cardAspectRatio).roundToDouble());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  canvas.drawRect(Offset.zero & size, Paint()..color = AppPalette.cardboard);
  SketchPainter(sketch.strokes).paint(canvas, size);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
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

  /// What [undo] takes back, latest last.
  final List<_PadAction> _history = [];

  /// What [redo] brings back, next last: what [undo] took back since the
  /// last stroke or clear.
  final List<_PadAction> _undone = [];
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

  /// Whether there's a stroke or a clear for [undo] to take back.
  bool get canUndo => _history.isNotEmpty;

  /// Whether there's something [undo] took back for [redo] to bring back.
  bool get canRedo => _undone.isNotEmpty;

  /// Takes back the latest stroke, or brings back every stroke the latest
  /// clear removed.
  void undo() {
    if (_history.isEmpty) return;
    final action = _history.removeLast();
    switch (action) {
      case _Drawn():
        _strokes.removeLast();
      case _Cleared(:final strokes):
        _strokes.addAll(strokes);
    }
    _undone.add(action);
    notifyListeners();
  }

  /// Does again what [undo] took back last: draws the stroke again, or
  /// clears the canvas again.
  void redo() {
    if (_undone.isEmpty) return;
    final action = _undone.removeLast();
    switch (action) {
      case _Drawn(:final stroke):
        _strokes.add(stroke);
      case _Cleared():
        _strokes.clear();
    }
    _history.add(action);
    notifyListeners();
  }

  /// Removes every stroke; [undo] brings them back.
  void clear() {
    if (_strokes.isEmpty) return;
    _history.add(_Cleared(List.of(_strokes)));
    _undone.clear();
    _strokes.clear();
    notifyListeners();
  }

  void lock() {
    enabled = false;
    notifyListeners();
  }

  void unlock() {
    enabled = true;
    notifyListeners();
  }

  void _begin(Offset point) {
    if (!enabled) return;
    final stroke = Stroke(color: color, width: width, points: [point]);
    _strokes.add(stroke);
    _history.add(_Drawn(stroke));
    _undone.clear();
    notifyListeners();
  }

  void _extend(Offset point) {
    if (!enabled || _strokes.isEmpty) return;
    _strokes.last.points.add(point);
    notifyListeners();
  }
}

/// A step [SketchPadController.undo] can take back.
sealed class _PadAction {
  const _PadAction();
}

/// A stroke drawn.
class _Drawn extends _PadAction {
  const _Drawn(this.stroke);

  final Stroke stroke;
}

/// The canvas cleared, with the [strokes] it removed.
class _Cleared extends _PadAction {
  const _Cleared(this.strokes);

  final List<Stroke> strokes;
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
