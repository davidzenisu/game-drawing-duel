/// No sound outside the web: nothing plays, and whether sound is on is only
/// kept while the app runs.
class SoundOutput {
  bool _on = false;

  /// Whether sound was turned on on this device.
  bool get savedOn => _on;

  /// Remembers whether sound is [on].
  void save(bool on) => _on = on;

  /// Lets sound play from now on (called on a tap).
  void wake() {}

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
