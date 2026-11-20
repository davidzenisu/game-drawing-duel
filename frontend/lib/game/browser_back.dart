import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/browser_history.dart';

/// Makes the browser's back button go back one screen in the game, on the
/// web, instead of leaving it (usually for the sign-in page before it).
///
/// It watches the app's navigator and keeps one browser history entry per
/// screen and dialog on it, the root screen included: back pops the top
/// one with [NavigatorState.maybePop], so screens that mustn't be left
/// (a running drawing, unsaved boosts) refuse or ask as with in-app back.
/// Back on the root screen asks "Leave the game?" and only then leaves.
///
/// Entries map to screens by index: entry 0 is the one the app opened on,
/// entry n stands for the n-th route on the navigator.
///
/// Chrome's back button skips entries the page added another entry from
/// without a tap or key in between (see [BrowserHistory]). So entries are
/// only added right after one, one per tap or key; until then a screen
/// opened on its own (a tutorial popping up) goes without one, and back
/// just pops the top screen. To get back to a screen's entry without one,
/// e.g. when a screen refuses back, the app moves forward through the
/// entries it already has, which Chrome never skips.
class BrowserBack extends NavigatorObserver {
  BrowserBack(this._history, {this.leaveCheckDelay = const Duration(seconds: 1)}) {
    final history = _history;
    if (history == null) return;
    // From before a reload, the entries back to the one the app opened on
    // then are the app's too: leaving goes back past them.
    final start = history.current;
    _skip = start == null ? 0 : start.skip + start.index;
    history
      ..replace(BrowserEntry(0, skip: _skip))
      ..onPop = _onPop
      ..onRestore = _onRestore
      ..onUserActivation = _onUserActivation;
  }

  final BrowserHistory? _history;

  /// How long leaving may take before the game counts as still open
  /// (nothing before it to go back to) and keeps handling back.
  final Duration leaveCheckDelay;

  late final int _skip;

  /// Routes on the navigator.
  int _depth = 0;

  /// The entry the browser is on, as far as the app knows.
  int _index = 0;

  /// The last of the app's entries: the ones after [_index] are forward.
  int _last = 0;

  /// The entry a [BrowserHistory.go] of the app's is on its way to.
  int? _goingTo;

  /// Whether the user tapped or typed since the app last added an entry.
  bool _activated = false;

  bool _syncQueued = false;
  bool _popping = false;
  bool _asking = false;

  /// Leaving the game after [_goingTo] is reached.
  bool _leaveQueued = false;
  bool _leaving = false;
  Timer? _leaveCheck;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed(1);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed(-1);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed(-1);

  void _changed(int by) {
    _depth += by;
    _queueSync();
  }

  void _onUserActivation() {
    _activated = true;
    // After the app handled the tap or key, e.g. opened a screen.
    _queueSync();
  }

  void _queueSync() {
    if (_history == null || _syncQueued) return;
    _syncQueued = true;
    // After the change is done: a pop and a push in a row cancel out.
    scheduleMicrotask(() {
      _syncQueued = false;
      _sync();
    });
  }

  /// Moves through or adds entries until there's one per route, as far as
  /// it can (see [BrowserBack]).
  void _sync() {
    final history = _history;
    if (history == null || _leaving || _popping || _goingTo != null) return;
    final target = _depth < 1 ? 1 : _depth;
    if (target < _index) {
      _goTo(target);
    } else if (target > _index && _last > _index) {
      _goTo(target < _last ? target : _last);
    } else if (target > _index && _activated && history.userActive) {
      _activated = false;
      history.push(BrowserEntry(++_index, skip: _skip));
      _last = _index;
    }
  }

  void _goTo(int index) {
    _goingTo = index;
    _history!.go(index - _index);
  }

  void _onPop(BrowserEntry? entry) {
    if (_leaving) return;
    final history = _history!;
    // Entries without the app's mark had it removed (the sign-in does so on
    // the entry it returns to): they can only be the first two.
    final index = entry?.index ?? (_index == 1 ? 0 : 1);
    if (entry == null) history.replace(BrowserEntry(index, skip: _skip));

    final goingTo = _goingTo;
    _goingTo = null;
    final from = _index;
    _index = index;
    if (index > _last) _last = index;
    if (goingTo == index) {
      // The app's own move.
      if (_leaveQueued) {
        _leave();
      } else {
        _sync();
      }
      return;
    }
    if (index >= from) {
      // Forward: back to where the screens are.
      _sync();
    } else if (_depth <= 1) {
      // Back on the root screen.
      _sync();
      unawaited(_askLeave());
    } else {
      unawaited(_popScreens(from - index));
    }
  }

  /// Back [count] screens, as far as they let.
  Future<void> _popScreens(int count) async {
    _popping = true;
    try {
      for (var i = 0; i < count && _depth > 1; i++) {
        final before = _depth;
        await navigator?.maybePop();
        // Refused or asking (a dialog came up): stop there.
        if (_depth >= before) break;
      }
    } finally {
      _popping = false;
      _sync();
    }
  }

  Future<void> _askLeave() async {
    final context = navigator?.context;
    if (_asking || context == null || !context.mounted) return;
    _asking = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the game?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Leave')),
        ],
      ),
    );
    _asking = false;
    if (leave != true) return;
    if (_goingTo != null) {
      _leaveQueued = true;
    } else {
      _leave();
    }
  }

  /// Goes back to the page before the game.
  void _leave() {
    _leaveQueued = false;
    _leaving = true;
    _history!.go(-(_index + 1 + _skip));
    // Still here after a while: there was nothing before the game.
    _leaveCheck?.cancel();
    _leaveCheck = Timer(leaveCheckDelay, _onRestore);
  }

  /// Back in the game after leaving it (forward, or nothing to go back to).
  void _onRestore() {
    _leaveCheck?.cancel();
    _leaveQueued = false;
    _leaving = false;
    _goingTo = null;
    _index = _history!.current?.index ?? 0;
    _sync();
  }
}
