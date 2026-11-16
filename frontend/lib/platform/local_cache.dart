/// Small answers of the API kept on the device between visits: in the
/// browser's local storage on the web, nowhere elsewhere.
library;

export 'local_cache_stub.dart' if (dart.library.js_interop) 'local_cache_web.dart';
