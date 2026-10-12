import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/drawing_screen.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';

void main() {
  testWidgets('every hurry takes 10% of the time left when it hits', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: DrawingScreen(
          subject: 'Sam',
          prompt: '"Sauna Lord"',
          hint: 'A challenger prompt',
          rarity: Rarity.hero,
          timeLimit: challengerDrawTime,
          hurries: [
            HurryPlan(by: 'Alex', atFraction: 0.25),
            HurryPlan(by: 'Robin', atFraction: 0.5),
          ],
        ),
      ),
    );
    expect(find.text('1:30'), findsOneWidget);
    final canvas = tester.getRect(find.byType(SketchPad));

    // 22.5s in, Alex's hurry takes 10% of the 67.5s left.
    await tester.pump(const Duration(milliseconds: 22700));
    expect(find.text('Alex sent a hurry! -6s'), findsOneWidget);
    // Once the banner is in, the canvas is as big as before.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(find.byType(SketchPad)), canvas, reason: 'the banner floats over the canvas');
    // The banner goes away after a few seconds.
    await tester.pump(const Duration(seconds: 4));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: find.text('Alex sent a hurry! -6s'), matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      0,
    );
    // 45s in, Robin's takes 10% of the 38.25s then left.
    await tester.pump(const Duration(milliseconds: 18100));
    expect(find.text('Robin sent a hurry! -3s'), findsOneWidget);
    expect(tester.getRect(find.byType(SketchPad)), canvas);
    // 90s - 45.2s - 10.575s of hurries.
    expect(find.text('0:34'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
