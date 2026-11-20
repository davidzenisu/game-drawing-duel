import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _kind = 'drawingDuel';
const _before = 'drawingDuelBefore';

/// Turns the browser's back button into a call to the app, instead of
/// leaving the game.
///
/// It keeps one extra history entry, the guard, after the one the game
/// opened on. Back moves from the guard to that entry; the guard then
/// calls back and moves forward to the guard again. Chrome's back button
/// skips an entry the page added another one from without a tap or key in
/// between, so the guard is only ever added right after one, and never
/// added again from a back: moving forward is never skipped.
class BackGuard {
  /// The game's entries before the one it opened on, from before reloads:
  /// leaving goes back past them.
  int _gameEntriesBefore = 0;
  bool _onGuard = false;
  bool _leaving = false;
  void Function()? _onBack;

  void start(void Function() onBack) {
    _onBack = onBack;
    final state = _read(web.window.history.state);
    if (state != null) {
      _gameEntriesBefore = state.before + (state.guard ? 1 : 0);
    }
    web.window.history.replaceState(_state(guard: false), '');
    web.window.addEventListener('popstate', _onPopState.toJS);
    web.window.addEventListener('pageshow', _onPageShow.toJS);
    // The events that count as a tap or key for the browser.
    for (final type in ['pointerdown', 'pointerup', 'keydown']) {
      web.window.addEventListener(type, _onInput.toJS, true.toJS);
    }
  }

  /// Goes back to the page before the game.
  void leave() {
    _leaving = true;
    web.window.history.go(-((_onGuard ? 2 : 1) + _gameEntriesBefore));
    // Still here (nothing before the game): keep guarding.
    Future<void>.delayed(const Duration(seconds: 1), () => _leaving = false);
  }

  void _onInput(web.Event event) {
    if (_onGuard || _leaving || !web.window.navigator.userActivation.isActive) return;
    _onGuard = true;
    web.window.history.pushState(_state(guard: true), '');
  }

  void _onPopState(web.PopStateEvent event) {
    if (_leaving) return;
    // The sign-in clears the state of the entry it comes back to: the one
    // the game opened on.
    final guard = _read(event.state)?.guard ?? false;
    _onGuard = guard;
    if (guard) return;
    web.window.history.go(1);
    _onBack?.call();
  }

  /// Back from another page, through the browser's cache.
  void _onPageShow(web.PageTransitionEvent event) {
    if (!event.persisted) return;
    _leaving = false;
    _onGuard = _read(web.window.history.state)?.guard ?? false;
  }

  JSObject _state({required bool guard}) => JSObject()
    ..[_kind] = (guard ? 'guard' : 'start').toJS
    ..[_before] = _gameEntriesBefore.toJS;

  static ({bool guard, int before})? _read(JSAny? state) {
    if (state == null || !state.isA<JSObject>()) return null;
    final object = state as JSObject;
    final kind = object[_kind];
    if (kind == null || !kind.isA<JSString>()) return null;
    final before = object[_before];
    return (
      guard: (kind as JSString).toDart == 'guard',
      before: before != null && before.isA<JSNumber>() ? (before as JSNumber).toDartInt : 0,
    );
  }
}
