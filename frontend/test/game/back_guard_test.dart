import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/mockup/mock_game_session.dart';
import 'package:frontend/platform/back_guard.dart';

/// Stands in for the browser: [back] presses its back button.
class FakeBackGuard extends BackGuard {
  void Function()? _onBack;
  bool left = false;

  @override
  void start(void Function() onBack) => _onBack = onBack;

  @override
  void leave() => left = true;

  void back() => _onBack!();
}

void main() {
  Future<FakeBackGuard> openGame(WidgetTester tester) async {
    final guard = FakeBackGuard();
    await tester.pumpWidget(GameApp(session: MockGameSession(seed: 1), splash: false, backGuard: guard));
    await tester.pumpAndSettle();
    return guard;
  }

  Future<void> back(WidgetTester tester, FakeBackGuard guard) async {
    guard.back();
    await tester.pumpAndSettle();
  }

  testWidgets('browser back goes back one screen at a time, then asks before leaving', (tester) async {
    final guard = await openGame(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    for (final name in ['Menu', 'Submenu', 'Details']) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(name))));
      await tester.pumpAndSettle();
    }

    for (final (gone, shown) in [('Details', 'Submenu'), ('Submenu', 'Menu')]) {
      await back(tester, guard);
      expect(find.text(gone), findsNothing);
      expect(find.text(shown), findsOneWidget);
    }
    await back(tester, guard);
    expect(find.text('Menu'), findsNothing);
    expect(find.text('Leave the game?'), findsNothing);

    await back(tester, guard);
    expect(find.text('Leave the game?'), findsOneWidget);
    // Back again closes the question, and asks again after.
    await back(tester, guard);
    expect(find.text('Leave the game?'), findsNothing);
    await back(tester, guard);
    expect(find.text('Leave the game?'), findsOneWidget);
    expect(guard.left, isFalse);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Leave the game?'), findsNothing);
    expect(guard.left, isFalse);

    await back(tester, guard);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(guard.left, isTrue);
  });

  testWidgets('a screen that blocks back stays', (tester) async {
    final guard = await openGame(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const PopScope(canPop: false, child: Scaffold(body: Text('Drawing')))),
    );
    await tester.pumpAndSettle();

    await back(tester, guard);
    await back(tester, guard);
    expect(find.text('Drawing'), findsOneWidget);
    expect(find.text('Leave the game?'), findsNothing);
  });
}
