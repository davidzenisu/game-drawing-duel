import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Images and sounds are stored with Git LFS (see `.gitattributes`). A
/// checkout without Git LFS gets small text pointers in their place, which
/// still build but don't play or show in the app.
void main() {
  test('the bundled images and sounds are real files, not Git LFS pointers', () {
    final files = [
      File('assets/logo.png'),
      ...Directory('assets/sounds').listSync().whereType<File>(),
      ...Directory('web').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.png')),
    ];
    expect(files.length, greaterThan(3));
    for (final file in files) {
      final start = String.fromCharCodes(file.readAsBytesSync().take(40));
      expect(start, isNot(startsWith('version https://git-lfs')), reason: '${file.path} is a Git LFS pointer');
    }
  });
}
