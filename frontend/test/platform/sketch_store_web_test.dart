@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/platform/sketch_store.dart';

void main() {
  test('drawings stay in IndexedDB across stores until cleared', () async {
    await SketchStore().clear();
    expect(await SketchStore().read('a'), isNull);

    await SketchStore().write('a', '{"strokes":[]}');
    expect(await SketchStore().read('a'), '{"strokes":[]}');

    await SketchStore().clear();
    expect(await SketchStore().read('a'), isNull);
  });
}
