import 'package:flutter/material.dart';

import '../game/sound.dart';
import 'palette.dart';
import 'sound_splash.dart';

/// Material 3 themes derived from [AppPalette]. Buttons click when pressed
/// (with sound effects on): the main, filled ones with a brighter blip.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(seedColor: AppPalette.seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      splashFactory: SoundSplashFactory(sound.buttonTap),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(splashFactory: SoundSplashFactory(sound.buttonConfirm)),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {for (final platform in TargetPlatform.values) platform: const FadeForwardsPageTransitionsBuilder()},
      ),
    );
  }
}
