import 'package:flutter/material.dart';

/// Central colour palette for the whole app.
///
/// Widgets should reference these tokens (or the derived [ColorScheme])
/// instead of hard-coding colours.
abstract final class AppPalette {
  static const seed = Color(0xFF6750A4);

  // Card and standee materials.
  static const cardboard = Color(0xFFFBF9F4);
  static const cardboardEdge = Color(0xFFE2DDD2);
  static const ink = Color(0xFF1C1B1F);
  static const plastic = Color(0xFF7F95BC);
  static const plasticShade = Color(0xFF566C93);
  static const plasticHighlight = Color(0xFFB7C6E2);

  // JRPG-style nameplates.
  static const nameplateTop = Color(0xFF3238B8);
  static const nameplateBottom = Color(0xFF0A0B4D);
  static const nameplateBorder = Color(0xFFFFFFFF);
  static const nameplateText = Color(0xFFFFFFFF);

  // Rarity tiers (1 to 4 stars).
  static const rarityBasic = Color(0xFF8E9BA8);
  static const rarityAdventurer = Color(0xFF3FB27F);
  static const rarityHero = Color(0xFF9A5CF5);
  static const rarityLegend = Color(0xFFFFB627);

  // Gameplay accents.
  static const ticket = Color(0xFFFF8A3D);
  static const hurry = Color(0xFFE5484D);
  static const victory = Color(0xFF2FBF71);
  static const defeat = Color(0xFFD64545);
  static const hpHigh = Color(0xFF3FB27F);
  static const hpLow = Color(0xFFE5484D);

  // Elements unlocked through duplicate upgrades.
  static const elementFire = Color(0xFFFF6A2B);
  static const elementIce = Color(0xFF52C7F2);
  static const elementStorm = Color(0xFFB98CFF);

  /// Brush colours offered on the drawing canvas.
  static const brushes = [
    ink,
    Color(0xFFE5484D),
    Color(0xFFFF8A3D),
    Color(0xFFF5C518),
    Color(0xFF3FB27F),
    Color(0xFF3B82F6),
    Color(0xFF9A5CF5),
    Color(0xFFE85AAD),
  ];

  /// Colour used by the canvas eraser (the cardboard itself).
  static const eraser = cardboard;
}
