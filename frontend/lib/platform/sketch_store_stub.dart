/// Nothing is kept outside the web: every visit downloads the drawings again.
class SketchStore {
  /// The drawing of character [id] as the API sent it, or null.
  Future<String?> read(String id) async => null;

  Future<void> write(String id, String json) async {}

  Future<void> clear() async {}
}
