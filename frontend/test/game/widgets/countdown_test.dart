import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/widgets/countdown.dart';

void main() {
  testWidgets('counts down every second and calls back once at zero', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Countdown(
            endsAt: DateTime.now().add(const Duration(seconds: 65, milliseconds: 500)),
            label: 'Day 2',
            onDone: () => done++,
          ),
        ),
      ),
    );
    expect(find.text('Day 2 · 1:05 left'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(done, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Countdown(endsAt: DateTime.now().subtract(const Duration(seconds: 1)), onDone: () => done++),
        ),
      ),
    );
    expect(find.text('0:00 left'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(done, 1, reason: 'once');
    await tester.pumpWidget(const SizedBox());
  });
}
