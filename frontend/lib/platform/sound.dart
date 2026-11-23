/// The game's sound output: the Web Audio API on the web, silence
/// elsewhere. Plays the files in `assets/sounds/` and remembers on the
/// device whether sound is on.
library;

export 'sound_stub.dart' if (dart.library.js_interop) 'sound_web.dart';
