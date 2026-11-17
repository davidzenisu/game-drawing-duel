import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Buzzes the phone for [length], where the browser can (not on iPhones).
void buzz(Duration length) {
  try {
    web.window.navigator.vibrate(length.inMilliseconds.toJS);
  } catch (_) {
    // No vibration here.
  }
}
