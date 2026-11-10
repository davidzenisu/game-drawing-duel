/// Saves a file the app made, e.g. a drawing as PNG, through the browser's
/// downloads on the web; not available elsewhere ([canDownload]).
library;

export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
