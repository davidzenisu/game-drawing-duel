/// No sound outside the web: nothing plays, and the settings are only kept
/// while the app runs.
class SoundOutput {
  final _saved = <String, bool>{};

  /// Whether the setting [key] (e.g. music) was turned on on this device.
  bool savedOn(String key) => _saved[key] ?? false;

  /// Remembers whether the setting [key] is [on].
  void save(String key, bool on) => _saved[key] = on;

  /// Lets sound play from now on (called on a tap).
  void wake() {}

  /// Downloads and decodes [files] of `assets/sounds/` ahead of time.
  void preload(Iterable<String> files) {}

  /// Plays [file] of `assets/sounds/` once.
  void play(String file, {double volume = 1}) {}

  /// Plays [file] of `assets/sounds/` over and over until stopped.
  SoundLoop loop(String file, {double volume = 1}) => SoundLoop();
}

/// A sound playing over and over.
class SoundLoop {
  /// Fades to [value], from 0 (silent) to 1.
  set volume(double value) {}

  void stop() {}
}
