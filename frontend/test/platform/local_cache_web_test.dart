@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/platform/local_cache.dart';

void main() {
  test('answers stay in local storage across caches until cleared', () {
    LocalCache().clear();
    expect(LocalCache().read('ranking:123456'), isNull);

    LocalCache().write('ranking:123456', '{"day":7}');
    expect(LocalCache().read('ranking:123456'), '{"day":7}');

    LocalCache().clear();
    expect(LocalCache().read('ranking:123456'), isNull);
  });
}
