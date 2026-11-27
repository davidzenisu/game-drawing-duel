import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';

void main() {
  Future<SketchPadController> pad(WidgetTester tester) async {
    final controller = SketchPadController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(width: 200, height: 250, child: SketchPad(controller: controller)),
        ),
      ),
    );
    return controller;
  }

  Offset at(WidgetTester tester, double x, double y) => tester.getTopLeft(find.byType(SketchPad)) + Offset(x, y);

  Future<TestGesture> down(WidgetTester tester, PointerDeviceKind kind, int pointer, Offset position) =>
      tester.startGesture(position, kind: kind, pointer: pointer);

  /// Moves [gesture] right in [steps] steps of 10 pixels.
  Future<void> drawRight(WidgetTester tester, TestGesture gesture, int steps) async {
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
  }

  testWidgets('a pen draws its whole stroke, from where it touches down', (tester) async {
    final controller = await pad(tester);
    final pen = await down(tester, PointerDeviceKind.stylus, 1, at(tester, 20, 50));
    await drawRight(tester, pen, 10);
    await pen.up();

    expect(controller.strokes, hasLength(1));
    expect(controller.strokes.single.points, hasLength(11));
    expect(controller.strokes.single.points.first, const Offset(0.1, 0.2));
  });

  testWidgets('a pen tap draws a dot', (tester) async {
    final controller = await pad(tester);
    final pen = await down(tester, PointerDeviceKind.stylus, 1, at(tester, 20, 50));
    await pen.up();

    expect(controller.strokes.single.points, hasLength(1));
  });

  testWidgets('a palm touching down mid-stroke neither stops nor moves the pen\'s stroke', (tester) async {
    final controller = await pad(tester);
    final pen = await down(tester, PointerDeviceKind.stylus, 1, at(tester, 20, 50));
    await drawRight(tester, pen, 4);
    final palm = await down(tester, PointerDeviceKind.touch, 2, at(tester, 150, 220));
    await drawRight(tester, pen, 6);
    await palm.moveBy(const Offset(-5, -5));
    await pen.up();
    await palm.up();

    expect(controller.strokes, hasLength(1), reason: 'the palm draws nothing');
    final points = controller.strokes.single.points;
    expect(points, hasLength(11));
    expect(points.last, const Offset(0.6, 0.2), reason: 'the stroke follows the pen only');
  });

  testWidgets('a palm resting before the pen comes down is taken back', (tester) async {
    final controller = await pad(tester);
    final palm = await down(tester, PointerDeviceKind.touch, 2, at(tester, 150, 220));
    await palm.moveBy(const Offset(-3, 2));
    final pen = await down(tester, PointerDeviceKind.stylus, 1, at(tester, 20, 50));
    await drawRight(tester, pen, 5);
    await palm.moveBy(const Offset(-3, 2));
    await pen.up();
    await palm.up();

    expect(controller.strokes, hasLength(1), reason: "only the pen's stroke stays");
    expect(controller.strokes.single.points.first, const Offset(0.1, 0.2));
    expect(controller.strokes.single.points, hasLength(6));
    controller.undo();
    expect(controller.isEmpty, isTrue, reason: "the palm's stroke left nothing to undo");
  });

  testWidgets('touches touching down while the pen is down draw nothing', (tester) async {
    final controller = await pad(tester);
    final pen = await down(tester, PointerDeviceKind.stylus, 1, at(tester, 20, 50));
    await drawRight(tester, pen, 3);
    await pen.up();
    final pen2 = await down(tester, PointerDeviceKind.stylus, 3, at(tester, 20, 100));
    final palm = await down(tester, PointerDeviceKind.touch, 2, at(tester, 150, 220));
    await pen2.up();
    // The palm is still on the screen after the pen lifts: still not drawing.
    await palm.moveBy(const Offset(-20, 0));
    await palm.up();

    expect(controller.strokes, hasLength(2));
  });

  testWidgets('a finger draws again between pen strokes', (tester) async {
    final controller = await pad(tester);
    final pen = await down(tester, PointerDeviceKind.stylus, 1, at(tester, 20, 50));
    await drawRight(tester, pen, 3);
    await pen.up();
    final finger = await down(tester, PointerDeviceKind.touch, 2, at(tester, 20, 100));
    await drawRight(tester, finger, 3);
    await finger.up();

    expect(controller.strokes, hasLength(2));
    expect(controller.strokes.last.points, hasLength(4));
  });

  testWidgets('a second finger doesn\'t take over the first one\'s stroke', (tester) async {
    final controller = await pad(tester);
    final first = await down(tester, PointerDeviceKind.touch, 1, at(tester, 20, 50));
    await drawRight(tester, first, 2);
    final second = await down(tester, PointerDeviceKind.touch, 2, at(tester, 20, 200));
    await second.moveBy(const Offset(0, -20));
    await drawRight(tester, first, 2);
    await first.up();
    await second.up();

    expect(controller.strokes, hasLength(1));
    expect(controller.strokes.single.points.last, const Offset(0.3, 0.2));
  });

  testWidgets('a cancelled pen keeps what it drew', (tester) async {
    final controller = await pad(tester);
    final pen = await down(tester, PointerDeviceKind.stylus, 1, at(tester, 20, 50));
    await drawRight(tester, pen, 3);
    await pen.cancel();
    final pen2 = await down(tester, PointerDeviceKind.stylus, 1, at(tester, 20, 100));
    await drawRight(tester, pen2, 2);
    await pen2.up();

    expect(controller.strokes.map((s) => s.points.length), [4, 3]);
  });

  testWidgets('the mouse draws with its main button only', (tester) async {
    final controller = await pad(tester);
    final right = await tester.startGesture(
      at(tester, 20, 50),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await right.moveBy(const Offset(30, 0));
    await right.up();
    expect(controller.isEmpty, isTrue);

    final left = await tester.startGesture(at(tester, 20, 50), kind: PointerDeviceKind.mouse);
    await left.moveBy(const Offset(30, 0));
    await left.up();
    expect(controller.strokes, hasLength(1));
  });

  testWidgets('a locked pad draws nothing, and a stroke stops when it locks', (tester) async {
    final controller = await pad(tester);
    final pen = await down(tester, PointerDeviceKind.stylus, 1, at(tester, 20, 50));
    await drawRight(tester, pen, 2);
    controller.lock();
    await drawRight(tester, pen, 2);
    await pen.up();
    expect(controller.strokes.single.points, hasLength(3));

    final again = await down(tester, PointerDeviceKind.touch, 2, at(tester, 20, 100));
    await again.up();
    expect(controller.strokes, hasLength(1));
  });
}
