import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';

void main() {
  Future<SketchPadController> pad(WidgetTester tester) async {
    final controller = SketchPadController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: SizedBox(width: 200, height: 250, child: SketchPad(controller: controller))),
      ),
    );
    return controller;
  }

  Future<void> stroke(WidgetTester tester) =>
      tester.dragFrom(tester.getCenter(find.byType(SketchPad)), const Offset(40, 20));

  testWidgets('undo goes back through strokes and clears in order', (tester) async {
    final controller = await pad(tester);
    expect(controller.canUndo, isFalse);

    await stroke(tester);
    await stroke(tester);
    controller.clear();
    await stroke(tester);
    controller.clear();
    expect(controller.isEmpty, isTrue);

    // Clearing an empty canvas leaves nothing to undo.
    controller.clear();

    controller.undo();
    expect(controller.strokes, hasLength(1), reason: 'the latest clear comes back');
    controller.undo();
    expect(controller.isEmpty, isTrue, reason: 'the stroke drawn after the first clear goes');
    controller.undo();
    expect(controller.strokes, hasLength(2), reason: 'the first clear comes back');
    controller.undo();
    controller.undo();
    expect(controller.isEmpty, isTrue);
    expect(controller.canUndo, isFalse);
    controller.undo();
    expect(controller.isEmpty, isTrue);
  });

  testWidgets('a locked pad keeps its history', (tester) async {
    final controller = await pad(tester);
    await stroke(tester);
    controller.lock();
    await stroke(tester);
    expect(controller.strokes, hasLength(1), reason: 'no strokes while locked');
    controller.unlock();
    controller.undo();
    expect(controller.isEmpty, isTrue);
    expect(controller.canUndo, isFalse);
  });
}
