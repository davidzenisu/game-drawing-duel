/// A buzz of the phone of a chosen length: through the browser's vibration
/// on the web (where the platform's haptic feedback is at most a few
/// milliseconds long), a heavy haptic tap elsewhere.
library;

export 'buzz_stub.dart' if (dart.library.js_interop) 'buzz_web.dart';
