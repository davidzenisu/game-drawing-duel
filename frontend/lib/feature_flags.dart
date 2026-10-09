/// Compile-time feature flags, provided via `--dart-define` or
/// `--dart-define-from-file` (see `config/config.json.example`).
abstract final class FeatureFlags {
  /// Runs the offline mockup of the gameplay loop instead of the regular app.
  ///
  /// Everything happens in memory within a single session: no backend,
  /// database or authentication is involved.
  static const mockupGameplay = bool.fromEnvironment('MOCKUP_GAMEPLAY');
}
