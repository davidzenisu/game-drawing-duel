import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/screens/gacha_screen.dart';

void main() {
  Future<void> open(WidgetTester tester, PullConfirmDialog dialog) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(context: context, builder: (_) => dialog),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the confirmation shows the pulls and stars a pull spends', (tester) async {
    await open(tester, const PullConfirmDialog(count: 10, buy: 2));
    expect(find.text('Pull heroes'), findsOneWidget);
    expect(find.text('Do you want to use'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.byIcon(Icons.confirmation_number_rounded), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.text('to pull 10 heroes?'), findsOneWidget);
  });

  testWidgets('without stars to spend, only the pulls', (tester) async {
    await open(tester, const PullConfirmDialog(count: 1, buy: 0));
    expect(find.text('1'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.text('to pull 1 hero?'), findsOneWidget);
  });

  testWidgets('out of pulls, only the stars', (tester) async {
    await open(tester, const PullConfirmDialog(count: 1, buy: 1));
    expect(find.text('10'), findsOneWidget);
    expect(find.byIcon(Icons.confirmation_number_rounded), findsNothing);
  });

  testWidgets('it says yes or no', (tester) async {
    final answers = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await showDialog<bool>(context: context, builder: (_) => const PullConfirmDialog(count: 10, buy: 0)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    for (final button in ['Cancel', 'Pull']) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
    }
    expect(answers, [false, true]);
  });
}
