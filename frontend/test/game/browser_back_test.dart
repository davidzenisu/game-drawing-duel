import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/browser_back.dart';
import 'package:frontend/platform/browser_history.dart';

/// A tab's session history as Chrome keeps it: entries of other pages, then
/// the game's, with moves landing a moment later.
///
/// Like Chrome's back button, [back] skips the game's entries it added
/// another entry from without a tap or key in between ([tap]), until the
/// next one.
class FakeHistory implements BrowserHistory {
  FakeHistory({int otherPages = 1, List<BrowserEntry?> game = const [null]})
    : entries = [for (var i = 0; i < otherPages; i++) _Other(), ...game.map(_Game.new)],
      position = otherPages + game.length - 1;

  final List<Object> entries;
  int position;
  bool _tappedSinceMove = false;
  void Function(BrowserEntry? entry)? _onPop;
  void Function()? _onUserActivation;

  /// Whether the browser is on another page than the game.
  bool get left => entries[position] is _Other;

  /// The game's entries' marks.
  List<BrowserEntry?> get marks => [for (final e in entries) if (e is _Game) e.mark];

  /// The user taps or types in the game.
  void tap() {
    _tappedSinceMove = true;
    for (final e in entries) {
      if (e is _Game) e.skipped = false;
    }
    _onUserActivation?.call();
  }

  @override
  BrowserEntry? get current => switch (entries[position]) {
    _Game(:final mark) => mark,
    _ => null,
  };

  @override
  bool get userActive => _tappedSinceMove;

  @override
  void replace(BrowserEntry entry) => (entries[position] as _Game).mark = entry;

  @override
  void push(BrowserEntry entry) {
    if (!_tappedSinceMove) (entries[position] as _Game).skipped = true;
    entries
      ..removeRange(position + 1, entries.length)
      ..add(_Game(entry));
    position++;
    _tappedSinceMove = false;
  }

  @override
  void go(int delta) => Timer.run(() => _moveTo(position + delta));

  /// The browser's back button.
  void back() => Timer.run(() {
    var target = position - 1;
    while (target > 0 && entries[target] is _Game && (entries[target] as _Game).skipped) {
      target--;
    }
    _moveTo(target);
  });

  /// The browser's forward button.
  void forward() => go(1);

  void _moveTo(int target) {
    if (target < 0 || target >= entries.length) return;
    position = target;
    _tappedSinceMove = false;
    final entry = entries[target];
    if (entry is _Game) _onPop?.call(entry.mark);
  }

  @override
  set onPop(void Function(BrowserEntry? entry)? callback) => _onPop = callback;

  @override
  set onRestore(void Function()? callback) {}

  @override
  set onUserActivation(void Function()? callback) => _onUserActivation = callback;
}

class _Other {}

class _Game {
  _Game(this.mark);

  BrowserEntry? mark;

  /// Skipped by the back button.
  bool skipped = false;
}

/// A home screen that opens numbered screens, the ones in [guarded] with
/// back blocked; opening one in [withPopup] also opens a dialog on its own.
Widget _app(BrowserBack browserBack, {Set<int> guarded = const {}, Set<int> withPopup = const {}}) {
  Widget screen(int n) {
    final body = Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            Text('Screen $n'),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen(n + 1)));
                if (withPopup.contains(n + 1)) {
                  showDialog<void>(context: context, builder: (_) => const AlertDialog(title: Text('Popup')));
                }
              },
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

Future<void> _tap(WidgetTester tester, FakeHistory history, String text) async {
  history.tap();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester, FakeHistory history) async {
  history.back();
  await tester.pumpAndSettle();
}

/// The game with its first screen, tapped on once.
Future<FakeHistory> _start(WidgetTester tester, {Set<int> guarded = const {}, Set<int> withPopup = const {}}) async {
  final history = FakeHistory();
  await tester.pumpWidget(_app(BrowserBack(history), guarded: guarded, withPopup: withPopup));
  history.tap();
  await tester.pumpAndSettle();
  return history;
}

void main() {
  testWidgets('back goes back one screen at a time, however many in a row', (tester) async {
    final history = await _start(tester);
    expect(history.marks, [const BrowserEntry(0), const BrowserEntry(1)]);
    for (var i = 0; i < 3; i++) {
      await _tap(tester, history, 'Open');
    }
    expect(find.text('Screen 3'), findsOneWidget);
    expect(history.current, const BrowserEntry(4));

    for (final n in [2, 1, 0]) {
      await _back(tester, history);
      expect(find.text('Screen $n'), findsOneWidget);
      expect(history.left, isFalse);
    }
    expect(find.text('Leave the game?'), findsNothing);
    // On the first screen it asks, and never leaves on its own.
    for (var i = 0; i < 5; i++) {
      await _back(tester, history);
      expect(find.text('Leave the game?'), i.isEven ? findsOneWidget : findsNothing);
      expect(history.left, isFalse);
    }
  });

  testWidgets("leaving a screen in the app goes back over its entry", (tester) async {
    final history = await _start(tester);
    await _tap(tester, history, 'Open');
    await _tap(tester, history, 'Open');

    await _tap(tester, history, 'Close');
    expect(find.text('Screen 1'), findsOneWidget);
    expect(history.current, const BrowserEntry(2));
    // No screen to go forward to.
    history.forward();
    await tester.pumpAndSettle();
    expect(find.text('Screen 1'), findsOneWidget);
    expect(history.current, const BrowserEntry(2));
    // Opening another one moves forward again instead of adding an entry.
    await _tap(tester, history, 'Open');
    expect(history.current, const BrowserEntry(3));
    await _back(tester, history);
    await _back(tester, history);
    expect(find.text('Screen 0'), findsOneWidget);
    expect(history.left, isFalse);
  });

  testWidgets('back on the first screen asks before leaving the game', (tester) async {
    final history = await _start(tester);

    await _back(tester, history);
    expect(find.text('Leave the game?'), findsOneWidget);
    await _tap(tester, history, 'Stay');
    expect(find.text('Screen 0'), findsOneWidget);
    expect(find.text('Leave the game?'), findsNothing);
    expect(history.current, const BrowserEntry(1));

    await _back(tester, history);
    await _tap(tester, history, 'Leave');
    expect(history.left, isTrue);
    expect(history.position, 0);
    // The page is gone: the check whether it stayed never comes.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a popup that opens on its own goes first', (tester) async {
    final history = await _start(tester, withPopup: {2});
    await _tap(tester, history, 'Open');
    await _tap(tester, history, 'Open');
    expect(find.text('Popup'), findsOneWidget);

    await _back(tester, history);
    expect(find.text('Popup'), findsNothing);
    expect(find.text('Screen 2'), findsOneWidget);
    await _back(tester, history);
    expect(find.text('Screen 1'), findsOneWidget);
    await _back(tester, history);
    expect(find.text('Screen 0'), findsOneWidget);
    expect(history.left, isFalse);
  });

  testWidgets('a screen that blocks back stays, however often back is pressed', (tester) async {
    final history = await _start(tester, guarded: {2});
    await _tap(tester, history, 'Open');
    await _tap(tester, history, 'Open');

    for (var i = 0; i < 4; i++) {
      await _back(tester, history);
      expect(find.text('Screen 2'), findsOneWidget);
      expect(history.left, isFalse);
    }
  });

  testWidgets('with nothing before the game, leaving keeps it going', (tester) async {
    final history = FakeHistory(otherPages: 0);
    await tester.pumpWidget(_app(BrowserBack(history)));
    history.tap();
    await tester.pumpAndSettle();

    await _back(tester, history);
    await _tap(tester, history, 'Leave');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await _tap(tester, history, 'Open');
    await _back(tester, history);
    expect(find.text('Screen 0'), findsOneWidget);
    expect(find.text('Leave the game?'), findsNothing);
  });

  testWidgets('after a reload, leaving goes back past the entries from before it', (tester) async {
    final history = FakeHistory(game: const [BrowserEntry(0), BrowserEntry(1), BrowserEntry(2)]);
    await tester.pumpWidget(_app(BrowserBack(history)));
    history.tap();
    await tester.pumpAndSettle();
    expect(history.current, const BrowserEntry(1, skip: 2));

    await _back(tester, history);
    await _tap(tester, history, 'Leave');
    expect(history.left, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an entry whose mark the sign-in removed counts as the first', (tester) async {
    final history = await _start(tester);
    // The sign-in clears the state of the entry it comes back to.
    (history.entries[history.position] as _Game).mark = null;
    await _tap(tester, history, 'Open');

    await _back(tester, history);
    expect(find.text('Screen 0'), findsOneWidget);
    expect(find.text('Leave the game?'), findsNothing);
    expect(history.current, const BrowserEntry(1));
  });

  testWidgets('does nothing without a browser history', (tester) async {
    await tester.pumpWidget(_app(BrowserBack(null)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Screen 0'), findsOneWidget);
  });
}
