import 'package:web/web.dart' as web;

/// Small answers of the API in the browser's local storage, under keys that
/// start with [_prefix]. Without local storage (some private windows),
/// nothing is kept.
class LocalCache {
  static const _prefix = 'drawing-duel:';

  String? read(String key) {
    try {
      return web.window.localStorage.getItem('$_prefix$key');
    } catch (_) {
      return null;
    }
  }

  void write(String key, String value) {
    try {
      web.window.localStorage.setItem('$_prefix$key', value);
    } catch (_) {
      // Full or unavailable: it's asked for again next time.
    }
  }

  void clear() {
    try {
      final storage = web.window.localStorage;
      final keys = [
        for (var i = 0; i < storage.length; i++)
          if (storage.key(i) case final String key when key.startsWith(_prefix)) key,
      ];
      for (final key in keys) {
        storage.removeItem(key);
      }
    } catch (_) {
      // Nothing kept.
    }
  }
}
