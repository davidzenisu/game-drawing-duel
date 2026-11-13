import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/widgets/ticket_chip.dart';

/// A screen with the chip, its count driven by [tickets].
Widget _app(ValueNotifier<int> tickets) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      actions: [
        ValueListenableBuilder(
          valueListenable: tickets,
          builder: (_, n, _) => TicketChip(tickets: n),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('new pulls pop up in the middle, then fly into the chip', (tester) async {
    final tickets = ValueNotifier(3);
    await tester.pumpWidget(_app(tickets));
    expect(find.byType(PullsReceived), findsNothing, reason: 'nothing to celebrate at first');

    tickets.value = 5;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PullsReceived), findsOneWidget);
    expect(find.text('+2 pulls'), findsOneWidget);
    expect(find.text('3 pulls'), findsOneWidget, reason: 'the count goes up once they land');

    await tester.pumpAndSettle();
    expect(find.byType(PullsReceived), findsNothing);
    expect(find.text('5 pulls'), findsOneWidget);
  });

  testWidgets('spending pulls is not celebrated', (tester) async {
    final tickets = ValueNotifier(3);
    await tester.pumpWidget(_app(tickets));
    tickets.value = 2;
    await tester.pump();
    await tester.pump();
    expect(find.byType(PullsReceived), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('2 pulls'), findsOneWidget);
  });

  testWidgets('pulls earned on another screen are celebrated once you are back', (tester) async {
    final tickets = ValueNotifier(3);
    await tester.pumpWidget(_app(tickets));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Drawing'))));
    await tester.pumpAndSettle();

    tickets.value = 4;
    await tester.pumpAndSettle();
    expect(find.byType(PullsReceived), findsNothing, reason: 'not over the other screen');

    navigator.pop();
    // Once the page is gone.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('+1 pull'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('4 pulls'), findsOneWidget);
  });

  testWidgets('the chip counts up one pull at a time once the ticket lands', (tester) async {
    final tickets = ValueNotifier(3);
    await tester.pumpWidget(_app(tickets));
    tickets.value = 6;
    await tester.pump();
    await tester.pump();
    await tester.pump(PullsReceived.duration);
    await tester.pump();
    final seen = <String>{};
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      seen.add(tester.widget<Text>(find.textContaining(RegExp(r'^\d+ pulls$')).last).data!);
    }
    expect(seen, containsAll(['4 pulls', '5 pulls', '6 pulls']));
    await tester.pumpAndSettle();
    expect(find.text('6 pulls'), findsOneWidget);
  });

  testWidgets('pulls earned before a screen replaces another wait until you are back', (tester) async {
    // Like drawing: back on the hub just long enough to save it, then the
    // recap opens on top.
    final tickets = ValueNotifier(3);
    await tester.pumpWidget(_app(tickets));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Drawing'))));
    await tester.pumpAndSettle();
    navigator.pop();
    tickets.value = 4;
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Recap'))));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PullsReceived), findsNothing, reason: 'not over the recap');
    }
    // Like the fight result replacing the fight setup.
    navigator.pushReplacement(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Result'))));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PullsReceived), findsNothing, reason: 'not over the result');
    }

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PullsReceived), findsNothing, reason: 'not while the page slides away');
    await tester.pumpAndSettle();
    expect(find.text('4 pulls'), findsOneWidget);
  });

  testWidgets('the ticket lands on the chip', (tester) async {
    final tickets = ValueNotifier(3);
    await tester.pumpWidget(_app(tickets));
    final chip = tester.getCenter(find.byType(TicketChip));
    tickets.value = 4;
    await tester.pump();
    await tester.pump();
    // Done flying, just before it's gone.
    await tester.pump(PullsReceived.duration * 0.97);
    final ticket = tester.getCenter(
      find.descendant(of: find.byType(PullsReceived), matching: find.byIcon(Icons.confirmation_number_rounded)),
    );
    expect((ticket - chip).distance, lessThan(12));
    await tester.pumpAndSettle();
  });

  testWidgets('a tap on the chip shows your stars under it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(appBar: AppBar(actions: const [TicketChip(tickets: 3, stars: 17)])),
      ),
    );
    expect(find.text('17 stars'), findsNothing);
    await tester.tap(find.byType(TicketChip));
    await tester.pumpAndSettle();
    expect(find.text('17 stars'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('17 stars')).dy,
      greaterThan(tester.getBottomLeft(find.byType(Chip)).dy),
      reason: 'below the pulls',
    );
  });
}
