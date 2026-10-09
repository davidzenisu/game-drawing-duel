import 'package:flutter/material.dart';

import 'palette.dart';

/// Material 3 themes derived from [AppPalette].
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(seedColor: AppPalette.seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {for (final platform in TargetPlatform.values) platform: const FadeForwardsPageTransitionsBuilder()},
      ),
    );
  }
}
