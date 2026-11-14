import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Drawings in the browser's IndexedDB, by character id. A character's
/// drawing never changes, so nothing ever goes stale. Without IndexedDB (some
/// private windows), nothing is kept.
class SketchStore {
  static const _database = 'drawing-duel';
  static const _store = 'sketches';

  Future<web.IDBDatabase>? _opened;

  Future<web.IDBDatabase> _open() => _opened ??= () async {
    final request = web.window.indexedDB.open(_database, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result! as web.IDBDatabase).createObjectStore(_store);
    }).toJS;
    return (await _done(request))! as web.IDBDatabase;
  }();

  Future<web.IDBObjectStore> _objects(String mode) async =>
      (await _open()).transaction(_store.toJS, mode).objectStore(_store);

  /// The drawing of character [id] as the API sent it, or null.
  Future<String?> read(String id) async {
    final json = await _done((await _objects('readonly')).get(id.toJS));
    return json.isA<JSString>() ? (json! as JSString).toDart : null;
  }

  Future<void> write(String id, String json) async {
    await _done((await _objects('readwrite')).put(json.toJS, id.toJS));
  }

  Future<void> clear() async {
    await _done((await _objects('readwrite')).clear());
  }

  static Future<JSAny?> _done(web.IDBRequest request) {
    final result = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => result.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => result.completeError(
      StateError('IndexedDB failed: ${request.error?.message}'),
    )).toJS;
    return result.future;
  }
}
