import 'dart:typed_data';
import 'dart:ui' as ui;

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

  /// Starts a stroke at [point]; false if the pad is locked.
  bool _begin(Offset point) {
    if (!enabled) return false;
    final stroke = Stroke(color: color, width: width, points: [point]);
    _strokes.add(stroke);
    _history.add(_Drawn(stroke));
    _undone.clear();
    notifyListeners();
    return true;
  }

  /// Takes back the stroke [_begin] started last, as if it was never drawn:
  /// a palm's, once the pen comes down.
  void _discard(Stroke stroke) {
    if (_history.lastOrNull case _Drawn(stroke: final last) when identical(last, stroke)) {
      _history.removeLast();
      _strokes.remove(stroke);
      notifyListeners();
    }
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
///
/// Each stroke follows the one pointer that started it; other fingers or a
/// palm touching down meanwhile don't move it. While a pen is down, touches
/// don't draw (the hand resting on the screen), and a touch stroke already
/// going when the pen comes down was that hand: it's taken back.
class SketchPad extends StatefulWidget {
  const SketchPad({super.key, required this.controller});

  final SketchPadController controller;

  @override
  State<SketchPad> createState() => _SketchPadState();
}

class _SketchPadState extends State<SketchPad> {
  /// The pointer drawing the current stroke, and its stroke.
  int? _pointer;
  Stroke? _stroke;
  PointerDeviceKind? _kind;

  /// The pens touching the canvas.
  final Set<int> _pens = {};

  static bool _isPen(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus || kind == PointerDeviceKind.invertedStylus;

  void _down(PointerDownEvent event, Offset point) {
    if (event.kind == PointerDeviceKind.mouse && event.buttons & kPrimaryMouseButton == 0) return;
    final pen = _isPen(event.kind);
    if (pen) _pens.add(event.pointer);
    if (_pointer != null) {
      if (!pen || _isPen(_kind!)) return;
      // A touch was drawing when the pen came down: the hand holding it.
      widget.controller._discard(_stroke!);
      _end();
    }
    if (!pen && _pens.isNotEmpty) return;
    if (!widget.controller._begin(point)) return;
    _pointer = event.pointer;
    _stroke = widget.controller.strokes.last;
    _kind = event.kind;
  }

  void _move(PointerMoveEvent event, Offset point) {
    if (event.pointer != _pointer) return;
    // Locked meanwhile (time's up), or the stroke undone or cleared.
    if (!identical(widget.controller.strokes.lastOrNull, _stroke)) return _end();
    widget.controller._extend(point);
  }

  void _up(PointerEvent event) {
    _pens.remove(event.pointer);
    if (event.pointer == _pointer) _end();
  }

  void _end() {
    _pointer = null;
    _stroke = null;
    _kind = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        Offset normalise(Offset local) =>
            Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _down(event, normalise(event.localPosition)),
          onPointerMove: (event) => _move(event, normalise(event.localPosition)),
          onPointerUp: _up,
          onPointerCancel: _up,
          child: CustomPaint(
            painter: SketchPainter(controller.strokes, repaint: controller),
            size: size,
          ),
        );
      },
    );
  }
}
