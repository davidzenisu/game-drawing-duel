/// Asks before the page is closed or reloaded while a timed drawing runs,
/// on the web; does nothing elsewhere.
library;

export 'leave_guard_stub.dart' if (dart.library.js_interop) 'leave_guard_web.dart';
