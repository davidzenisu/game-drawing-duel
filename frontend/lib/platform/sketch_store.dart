/// Keeps downloaded drawings on the device between visits: in the browser's
/// IndexedDB on the web, nowhere elsewhere.
library;

export 'sketch_store_stub.dart' if (dart.library.js_interop) 'sketch_store_web.dart';
