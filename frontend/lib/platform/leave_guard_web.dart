import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Makes the browser ask "Leave site?" before the page is closed or
/// reloaded, while enabled.
class LeaveGuard {
  JSFunction? _listener;

  void enable() {
    if (_listener != null) return;
    final listener = ((web.Event event) {
      event.preventDefault();
      // Older browsers only ask when a return value is set.
      (event as web.BeforeUnloadEvent).returnValue = '';
    }).toJS;
    _listener = listener;
    web.window.addEventListener('beforeunload', listener);
  }

  void disable() {
    final listener = _listener;
    if (listener == null) return;
    web.window.removeEventListener('beforeunload', listener);
    _listener = null;
  }
}
