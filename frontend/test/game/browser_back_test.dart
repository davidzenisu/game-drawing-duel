import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/browser_back.dart';
import 'package:frontend/platform/browser_history.dart';

/// A tab's session history: entries of other pages, then the game's, with
/// moves landing a moment later like the browser's.
class FakeHistory implements BrowserHistory {
  FakeHistory({int otherPages = 1, List<BrowserEntry?> game = const [null]})
    : entries = [for (var i = 0; i < otherPages; i++) const _Other(), ...game.map(_Game.new)],
      position = otherPages + game.length - 1;

  final List<Object> entries;
  int position;
  void Function(BrowserEntry? entry)? _onPop;

  /// Whether the browser is on another page than the game.
  bool get left => entries[position] is _Other;

  /// The game's entries' marks.
  List<BrowserEntry?> get marks => [for (final e in entries) if (e is _Game) e.mark];

  @override
  BrowserEntry? get current => switch (entries[position]) {
    _Game(:final mark) => mark,
    _ => null,
  };

  @override
  void replace(BrowserEntry entry) => entries[position] = _Game(entry);

  @override
  void push(BrowserEntry entry) {
    entries
      ..removeRange(position + 1, entries.length)
      ..add(_Game(entry));
    position++;
  }

  @override
  void go(int delta) => Timer.run(() => _move(delta));

  void back() => go(-1);

  void forward() => go(1);

  void _move(int delta) {
    final target = position + delta;
    if (target < 0 || target >= entries.length) return;
    position = target;
    final entry = entries[target];
    if (entry is _Game) _onPop?.call(entry.mark);
  }

  @override
  set onPop(void Function(BrowserEntry? entry)? callback) => _onPop = callback;

  @override
  set onRestore(void Function()? callback) {}
}

class _Other {
  const _Other();
}

class _Game {
  const _Game(this.mark);

  final BrowserEntry? mark;
}

/// A home screen that opens numbered screens, the ones in [guarded] with
/// back blocked.
Widget _app(BrowserBack browserBack, {Set<int> guarded = const {}}) {
  Widget screen(int n) {
    final body = Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            Text('Screen $n'),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen(n + 1))),
              child: const Text('Open'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        ),
      ),
    );
    return guarded.contains(n) ? PopScope(canPop: false, child: body) : body;
  }

  return MaterialApp(navigatorObservers: [browserBack], home: screen(0));
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester, FakeHistory history) async {
  history.back();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('back goes back one screen, each with its own entry', (tester) async {
    final history = FakeHistory();
    await tester.pumpWidget(_app(BrowserBack(history)));
    await tester.pumpAndSettle();
    expect(history.marks, [const BrowserEntry(0), const BrowserEntry(1)]);

    await _open(tester);
    await _open(tester);
    expect(find.text('Screen 2'), findsOneWidget);
    expect(history.current, const BrowserEntry(3));

    await _back(tester, history);
    expect(find.text('Screen 1'), findsOneWidget);
    expect(history.current, const BrowserEntry(2));
    await _back(tester, history);
    expect(find.text('Screen 0'), findsOneWidget);
    expect(history.current, const BrowserEntry(1));
    expect(history.left, isFalse);
  });

  testWidgets("leaving a screen in the app goes back over its entry", (tester) async {
    final history = FakeHistory();
    await tester.pumpWidget(_app(BrowserBack(history)));
    await _open(tester);
    await _open(tester);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Screen 1'), findsOneWidget);
    expect(history.current, const BrowserEntry(2));
    // No screen to go forward to.
    history.forward();
    await tester.pumpAndSettle();
    expect(find.text('Screen 1'), findsOneWidget);
    expect(history.current, const BrowserEntry(2));
  });

  testWidgets('back on the first screen asks before leaving the game', (tester) async {
    final history = FakeHistory();
    await tester.pumpWidget(_app(BrowserBack(history)));
    await tester.pumpAndSettle();

    await _back(tester, history);
    expect(find.text('Leave the game?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Screen 0'), findsOneWidget);
    expect(history.current, const BrowserEntry(1));

    // Back closes the question too.
    await _back(tester, history);
    await _back(tester, history);
    expect(find.text('Leave the game?'), findsNothing);
    expect(history.current, const BrowserEntry(1));

    await _back(tester, history);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(history.left, isTrue);
    expect(history.position, 0);
    // The page is gone: the check whether it stayed never comes.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('with nothing before the game, leaving keeps it going', (tester) async {
    final history = FakeHistory(otherPages: 0);
    await tester.pumpWidget(_app(BrowserBack(history)));
    await tester.pumpAndSettle();

    await _back(tester, history);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(history.current, const BrowserEntry(1));
    await _open(tester);
    await _back(tester, history);
    expect(find.text('Screen 0'), findsOneWidget);
    expect(history.current, const BrowserEntry(1));
  });

  testWidgets('a screen that blocks back keeps its entry', (tester) async {
    final history = FakeHistory();
    await tester.pumpWidget(_app(BrowserBack(history), guarded: {1}));
    await _open(tester);

    await _back(tester, history);
    expect(find.text('Screen 1'), findsOneWidget);
    expect(history.current, const BrowserEntry(2));
    expect(history.marks, hasLength(3));
  });

  testWidgets('after a reload, leaving goes back past the entries from before it', (tester) async {
    final history = FakeHistory(game: const [BrowserEntry(0), BrowserEntry(1), BrowserEntry(2)]);
    await tester.pumpWidget(_app(BrowserBack(history)));
    await tester.pumpAndSettle();
    expect(history.current, const BrowserEntry(1, skip: 2));

    await _back(tester, history);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(history.left, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an entry whose mark the sign-in removed counts as the first', (tester) async {
    final history = FakeHistory();
    await tester.pumpWidget(_app(BrowserBack(history)));
    await tester.pumpAndSettle();
    // The sign-in clears the state of the entry it comes back to.
    history.entries[history.position] = const _Game(null);
    await _open(tester);

    await _back(tester, history);
    expect(find.text('Screen 0'), findsOneWidget);
    expect(find.text('Leave the game?'), findsNothing);
    expect(history.current, const BrowserEntry(1));
  });

  testWidgets('does nothing without a browser history', (tester) async {
    await tester.pumpWidget(_app(BrowserBack(null)));
    await _open(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Screen 0'), findsOneWidget);
  });
}
