import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/screens/drawing_recap_screen.dart';
import 'package:frontend/game/screens/drawing_screen.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';

void main() {
  testWidgets('every hurry takes 5s when it hits, at its time left', (tester) async {
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
            HurryPlan(by: 'Alex', left: Duration(seconds: 45)),
            HurryPlan(by: 'Robin', left: Duration(seconds: 26)),
          ],
        ),
      ),
    );
    expect(find.text('1:00'), findsOneWidget);
    final canvas = tester.getRect(find.byType(SketchPad));

    // 15s in, with 45s left, Alex's hurry takes 5s.
    await tester.pump(const Duration(milliseconds: 15200));
    expect(find.text('Alex sent a hurry! -5s'), findsOneWidget);
    // Once the banner is in, the canvas is as big as before.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(find.byType(SketchPad)), canvas, reason: 'the banner floats over the canvas');
    // The banner goes away after a few seconds.
    await tester.pump(const Duration(seconds: 4));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: find.text('Alex sent a hurry! -5s'), matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      0,
    );
    // 29s in, with 26s left, Robin's takes 5s too.
    await tester.pump(const Duration(milliseconds: 10600));
    expect(find.text('Robin sent a hurry! -5s'), findsOneWidget);
    expect(tester.getRect(find.byType(SketchPad)), canvas);
    // 60s - 30.2s - 10s of hurries.
    expect(find.text('0:19'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  Future<DrawingResult?> drawWithHurries(
    WidgetTester tester,
    List<String> senders,
    double jitter,
    Set<String> seen,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DrawingResult? result;
    final hits = Hurries.hits([for (final _ in senders) jitter]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => result = await Navigator.of(context).push<DrawingResult>(
              MaterialPageRoute(
                builder: (_) => DrawingScreen(
                  subject: 'Sam',
                  prompt: '"Sauna Lord"',
                  hint: 'A challenger prompt',
                  rarity: Rarity.hero,
                  initialTitle: 'Sauna Lord',
                  titleLocked: true,
                  timeLimit: challengerDrawTime,
                  hurries: [for (final (i, by) in senders.indexed) HurryPlan(by: by, left: hits[i])],
                ),
              ),
            ),
            child: const Text('Draw'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    final pad = tester.getRect(find.byType(SketchPad));
    await tester.dragFrom(pad.center, const Offset(80, 40));
    // Draw until under 15s are left, noting every hurry banner.
    final under15 = find.textContaining(RegExp(r'^0:(1[0-4]|0\d)$'));
    void note() => seen.addAll([for (final text in tester.widgetList<Text>(find.textContaining(' sent '))) text.data!]);
    note();
    for (var i = 0; i < 300 && under15.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      note();
    }
    expect(under15, findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    return result;
  }

  testWidgets('a few hurries hit one by one, all before the last 15s', (tester) async {
    final seen = <String>{};
    final result = await drawWithHurries(tester, ['Alex', 'Sam', 'Robin', 'Kim'], 0.5, seen);
    expect(seen, {
      for (final by in ['Alex', 'Sam', 'Robin', 'Kim']) '$by sent a hurry! -5s',
    });
    expect(result!.hurriedBy, ['Alex', 'Sam', 'Robin', 'Kim']);
  });

  testWidgets('a full day of hurries all hit before the last 15s, together if they must', (tester) async {
    final senders = ['Alex', 'Sam', 'Robin', 'Kim', 'Jo', 'Lee', 'Max', 'Ana', 'Tom'];
    final seen = <String>{};
    final result = await drawWithHurries(tester, senders, 0.9, seen);
    // 9 cuts of 5s fill the 40s from 55s to 15s left: they hit at once.
    expect(seen, {'Alex, Sam and 7 more sent hurries! -45s'});
    expect(result!.hurriedBy, senders);
  });

  test('hurries are spread between 55s and 15s left', () {
    for (final n in [1, 2, 4, 9]) {
      for (final jitter in [0.0, 0.5, 0.999]) {
        final hits = Hurries.hits(List.filled(n, jitter));
        expect(
          hits,
          everyElement(predicate<Duration>((d) => d >= Hurries.lastLeft && d <= Hurries.firstLeft)),
          reason: '$n × $jitter',
        );
        for (var i = 1; i < n; i++) {
          // The next one only hits once the time the one before took is gone.
          expect(
            hits[i],
            lessThanOrEqualTo(hits[i - 1] - Hurries.cut + const Duration(microseconds: 1)),
            reason: '$n × $jitter',
          );
        }
      }
    }
  });

  testWidgets('once the clock runs there is no backing out, and the result lists every hurry', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DrawingResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => result = await Navigator.of(context).push<DrawingResult>(
              MaterialPageRoute(
                builder: (_) => const DrawingScreen(
                  subject: 'Sam',
                  prompt: '"Sauna Lord"',
                  hint: 'A challenger prompt',
                  rarity: Rarity.hero,
                  initialTitle: 'Sauna Lord',
                  titleLocked: true,
                  timeLimit: challengerDrawTime,
                  noBackingOut: true,
                  hurries: [
                    HurryPlan(by: 'Alex', left: Duration(seconds: 45)),
                    HurryPlan(by: 'Robin', left: Duration(seconds: 26)),
                  ],
                ),
              ),
            ),
            child: const Text('Draw'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsNothing, reason: 'no back button while the clock runs');

    // The system back is refused too.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(DrawingScreen), findsOneWidget);
    expect(find.textContaining("There's no starting over"), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(DrawingScreen))).hideCurrentSnackBar();
    // Draw a line, 20s in: Alex's hurry hit, Robin's not yet.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    final pad = tester.getRect(find.byType(SketchPad));
    await tester.dragFrom(pad.center, const Offset(80, 40));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawingScreen), findsNothing);
    expect(result!.title, 'Sauna Lord');
    expect(result!.hurriedBy, ['Alex', 'Robin'], reason: "Robin's counts though it didn't hit yet");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('running out of time with nothing drawn lets you leave', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<DrawingResult>(
                builder: (_) => const DrawingScreen(
                  subject: 'Sam',
                  prompt: '"Sauna Lord"',
                  hint: 'A challenger prompt',
                  rarity: Rarity.hero,
                  timeLimit: challengerDrawTime,
                  noBackingOut: true,
                ),
              ),
            ),
            child: const Text('Draw'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 61));
    expect(find.byType(BackButton), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DrawingScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the recap shows the drawing, its nameplate and every hurry on one phone screen', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const sketch = Sketch([
      Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
    ]);
    await tester.pumpWidget(
      const MaterialApp(
        home: DrawingRecapScreen(
          subject: 'Sam',
          result: DrawingResult(sketch, 'Lord of the Top Sauna Bench', hurriedBy: ['Alex', 'Robin', 'Kim']),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'it all fits one screen');
    for (final text in ['Sam', 'Lord of the Top Sauna Bench', '3 hurries', 'Alex', 'Robin', 'Kim']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.byType(SketchView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('while the title is typed, a tap on the canvas only hides the keyboard', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: DrawingScreen(subject: 'Sam', prompt: 'Basic', hint: 'Them by day', rarity: Rarity.basic),
      ),
    );
    final pad = tester.widget<SketchPad>(find.byType(SketchPad)).controller;
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    final canvas = tester.getRect(find.byType(SketchPad));
    await tester.dragFrom(canvas.center, const Offset(60, 30));
    await tester.pump();
    expect(pad.isEmpty, isTrue, reason: 'no stroke by mistake');
    expect(tester.testTextInput.isVisible, isFalse, reason: 'the keyboard is hidden');

    // With the keyboard gone, the canvas draws again.
    await tester.dragFrom(tester.getRect(find.byType(SketchPad)).center, const Offset(60, 30));
    await tester.pump();
    expect(pad.isEmpty, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a prompt's title shows at the top only, and the tools say which width is on", (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: DrawingScreen(
          subject: 'Sam',
          prompt: '"Sauna Lord"',
          hint: 'A challenger prompt',
          rarity: Rarity.hero,
          initialTitle: 'Sauna Lord',
          titleLocked: true,
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('"Sauna Lord"'), findsOneWidget);

    BoxBorder? ringOf(int i) =>
        (tester
                    .widget<AnimatedContainer>(
                      find
                          .ancestor(of: find.byIcon(Icons.circle).at(i), matching: find.byType(AnimatedContainer))
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .border;
    final selected = brushWidths.indexOf(tester.widget<SketchPad>(find.byType(SketchPad)).controller.width);
    expect(ringOf(selected), isA<Border>().having((b) => b.top.color, 'color', isNot(Colors.transparent)));
    expect(
      ringOf((selected + 1) % brushWidths.length),
      isA<Border>().having((b) => b.top.color, 'color', Colors.transparent),
    );
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    await tester.pumpWidget(const SizedBox());
  });
}
