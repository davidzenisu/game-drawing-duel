import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/mockup/mock_game_session.dart';

void main() {
  /// The game, with the platform's "leave" calls recorded.
  Future<List<String>> openGame(WidgetTester tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(GameApp(session: MockGameSession(seed: 1), splash: false));
    await tester.pumpAndSettle();
    return calls;
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('back on the first screen asks before leaving the game', (tester) async {
    final calls = await openGame(tester);

    await back(tester);
    expect(find.text('Leave the game?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Leave the game?'), findsNothing);
    expect(calls, isNot(contains('SystemNavigator.pop')));

    // Back closes the question too.
    await back(tester);
    await back(tester);
    expect(find.text('Leave the game?'), findsNothing);
    expect(calls, isNot(contains('SystemNavigator.pop')));

    await back(tester);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(calls, contains('SystemNavigator.pop'));
  });

  testWidgets('back several screens deep goes back one screen at a time, then asks', (tester) async {
    final calls = await openGame(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    for (final name in ['Menu', 'Submenu', 'Details']) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(name))));
      await tester.pumpAndSettle();
    }

    for (final (gone, shown) in [('Details', 'Submenu'), ('Submenu', 'Menu')]) {
      await back(tester);
      expect(find.text(gone), findsNothing);
      expect(find.text(shown), findsOneWidget);
      expect(find.text('Leave the game?'), findsNothing);
    }
    await back(tester);
    expect(find.text('Menu'), findsNothing);
    expect(find.text('Leave the game?'), findsNothing);

    await back(tester);
    expect(find.text('Leave the game?'), findsOneWidget);
    expect(calls, isNot(contains('SystemNavigator.pop')));
  });
}
