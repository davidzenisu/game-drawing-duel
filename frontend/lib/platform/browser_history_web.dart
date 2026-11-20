import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'browser_history_api.dart';

/// The page's session history.
BrowserHistory? browserHistory() => _WebHistory();

const _indexKey = 'drawingDuelBack';
const _skipKey = 'drawingDuelSkip';

class _WebHistory implements BrowserHistory {
  void Function(BrowserEntry? entry)? _onPop;
  void Function()? _onRestore;
  void Function()? _onUserActivation;
  JSFunction? _popListener;
  JSFunction? _showListener;
  JSFunction? _activationListener;

  @override
  BrowserEntry? get current => _read(web.window.history.state);

  @override
  void replace(BrowserEntry entry) => web.window.history.replaceState(_write(entry), '');

  @override
  void push(BrowserEntry entry) => web.window.history.pushState(_write(entry), '');

  @override
  bool get userActive => web.window.navigator.userActivation.isActive;

  @override
  void go(int delta) => web.window.history.go(delta);

  @override
  set onPop(void Function(BrowserEntry? entry)? callback) {
    _onPop = callback;
    if (callback != null && _popListener == null) {
      final listener = ((web.PopStateEvent event) => _onPop?.call(_read(event.state))).toJS;
      _popListener = listener;
      web.window.addEventListener('popstate', listener);
    } else if (callback == null && _popListener != null) {
      web.window.removeEventListener('popstate', _popListener);
      _popListener = null;
    }
  }

  @override
  set onRestore(void Function()? callback) {
    _onRestore = callback;
    if (callback != null && _showListener == null) {
      final listener = ((web.PageTransitionEvent event) {
        if (event.persisted) _onRestore?.call();
      }).toJS;
      _showListener = listener;
      web.window.addEventListener('pageshow', listener);
    } else if (callback == null && _showListener != null) {
      web.window.removeEventListener('pageshow', _showListener);
      _showListener = null;
    }
  }

  /// The events that count as a user activation: mouse presses, the end
  /// of touches and pen strokes, and keys.
  @override
  set onUserActivation(void Function()? callback) {
    _onUserActivation = callback;
    const events = ['pointerdown', 'pointerup', 'keydown'];
    if (callback != null && _activationListener == null) {
      final listener = ((web.Event event) {
        if (event.isA<web.PointerEvent>()) {
          final mouse = (event as web.PointerEvent).pointerType == 'mouse';
          if (mouse != (event.type == 'pointerdown')) return;
        }
        _onUserActivation?.call();
      }).toJS;
      _activationListener = listener;
      for (final type in events) {
        web.window.addEventListener(type, listener, true.toJS);
      }
    } else if (callback == null && _activationListener != null) {
      for (final type in events) {
        web.window.removeEventListener(type, _activationListener, true.toJS);
      }
      _activationListener = null;
    }
  }

  static JSObject _write(BrowserEntry entry) => JSObject()
    ..[_indexKey] = entry.index.toJS
    ..[_skipKey] = entry.skip.toJS;

  static BrowserEntry? _read(JSAny? state) {
    if (state == null || !state.isA<JSObject>()) return null;
    final object = state as JSObject;
    final index = object[_indexKey];
    if (index == null || !index.isA<JSNumber>()) return null;
    final skip = object[_skipKey];
    return BrowserEntry(
      (index as JSNumber).toDartInt,
      skip: skip != null && skip.isA<JSNumber>() ? (skip as JSNumber).toDartInt : 0,
    );
  }
}
