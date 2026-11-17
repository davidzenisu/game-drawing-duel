import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/screens/gacha_screen.dart';

void main() {
  String spending({required int count, required int tickets, required int stars, required int buy}) =>
      PullConfirmDialog(count: count, banner: GachaBanner.standard, tickets: tickets, stars: stars, buy: buy).spending;

  test('the confirmation says what a pull spends', () {
    expect(spending(count: 10, tickets: 14, stars: 50, buy: 0), 'Uses 10 pulls of your 14.');
    expect(spending(count: 1, tickets: 1, stars: 0, buy: 0), 'Uses 1 pull of your 1.');
    expect(
      spending(count: 10, tickets: 3, stars: 80, buy: 7),
      'Uses your 3 pulls, and 70 of your 80 stars buy the other 7 (10 stars a pull).',
    );
    expect(
      spending(count: 1, tickets: 0, stars: 25, buy: 1),
      "You're out of pulls: 10 of your 25 stars buy this one (10 stars a pull).",
    );
    expect(
      spending(count: 10, tickets: 0, stars: 100, buy: 10),
      "You're out of pulls: 100 of your 100 stars buy all 10 (10 stars a pull).",
    );
  });

  testWidgets('the confirmation shows the stars on its button, and says yes or no', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await showDialog<bool>(
              context: context,
              builder: (_) =>
                  const PullConfirmDialog(count: 10, banner: GachaBanner.weekly, tickets: 3, stars: 80, buy: 7),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Pull ×10 on the weekly banner?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull · 70 ★'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });
}
