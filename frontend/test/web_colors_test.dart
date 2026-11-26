import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/palette.dart';

String _hex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  test('the surface tokens are the themes\' backgrounds', () {
    expect(ColorScheme.fromSeed(seedColor: AppPalette.seed).surface, AppPalette.surfaceLight);
    expect(
      ColorScheme.fromSeed(seedColor: AppPalette.seed, brightness: Brightness.dark).surface,
      AppPalette.surfaceDark,
    );
  });

  test('the installed web app uses the themes\' backgrounds', () {
    final light = _hex(AppPalette.surfaceLight);
    final dark = _hex(AppPalette.surfaceDark);
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('media="(prefers-color-scheme: light)" content="$light"'));
    expect(html, contains('media="(prefers-color-scheme: dark)" content="$dark"'));
    final manifest = File('web/manifest.json').readAsStringSync();
    expect(manifest, contains('"theme_color": "$dark"'));
    expect(manifest, contains('"background_color": "$dark"'));
  });
}
