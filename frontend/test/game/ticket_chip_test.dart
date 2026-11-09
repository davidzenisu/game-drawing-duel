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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('+1 pull'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('4 pulls'), findsOneWidget);
  });
}
