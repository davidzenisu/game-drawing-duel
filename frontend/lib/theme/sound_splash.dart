import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// An ink splash that also plays [sound] as it starts: every Material button,
/// icon button, menu item or list row makes its sound when pressed, through
/// the theme. Draws the same splash as the theme's default.
class SoundSplashFactory extends InteractiveInkFeatureFactory {
  const SoundSplashFactory(this.sound);

  /// Played as a press starts the splash.
  final VoidCallback sound;

  /// Material 3's default splash: a ripple on the web, a sparkle elsewhere.
  static InteractiveInkFeatureFactory get _splash => kIsWeb ? InkRipple.splashFactory : InkSparkle.splashFactory;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    sound();
    return _splash.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
    );
  }
}
