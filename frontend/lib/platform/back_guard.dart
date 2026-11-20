/// Keeps the browser's back button in the game, on the web (see
/// `BackGuard`); does nothing elsewhere.
library;

export 'back_guard_stub.dart' if (dart.library.js_interop) 'back_guard_web.dart';
