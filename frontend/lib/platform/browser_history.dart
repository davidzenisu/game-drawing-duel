/// The browser's session history, for browser back to pop the app's
/// screens (see `BrowserBack`); there is none outside the web.
library;

export 'browser_history_api.dart';
export 'browser_history_stub.dart' if (dart.library.js_interop) 'browser_history_web.dart';
