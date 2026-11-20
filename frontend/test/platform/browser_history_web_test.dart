@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/platform/browser_history.dart';

void main() {
  test("marks entries with the game's index and reads them back", () {
    final history = browserHistory()!;
    history.replace(const BrowserEntry(0, skip: 2));
    expect(history.current, const BrowserEntry(0, skip: 2));

    history.push(const BrowserEntry(1, skip: 2));
    expect(history.current, const BrowserEntry(1, skip: 2));
  });
}
