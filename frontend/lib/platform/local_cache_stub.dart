/// Nothing is kept outside the web: every visit asks the API again.
class LocalCache {
  String? read(String key) => null;

  void write(String key, String value) {}

  /// Forgets everything this cache kept.
  void clear() {}
}
