import 'dart:ui';

import '../../theme/palette.dart';
import 'themes.dart';

/// Rarity tiers of the gacha, which also define how long a drawing may take.
enum Rarity {
  basic(stars: 1, label: 'Basic', drawTime: Duration(seconds: 30), color: AppPalette.rarityBasic),
  adventurer(stars: 2, label: 'Adventurer', drawTime: Duration(minutes: 1), color: AppPalette.rarityAdventurer),
  hero(stars: 3, label: 'Hero', drawTime: Duration(minutes: 2), color: AppPalette.rarityHero),
  legend(stars: 4, label: 'Legend', drawTime: null, color: AppPalette.rarityLegend);

  const Rarity({required this.stars, required this.label, required this.drawTime, required this.color});

  final int stars;
  final String label;

  /// Time limit for drawing a character of this tier; `null` means unlimited.
  final Duration? drawTime;
  final Color color;
}

class Player {
  const Player({required this.id, required this.name, this.isYou = false});

  final String id;
  final String name;
  final bool isYou;

  Player copyWith({String? name, bool? isYou}) => Player(id: id, name: name ?? this.name, isYou: isYou ?? this.isYou);
}

/// A single pen stroke. Points are normalised to the canvas (0..1 on both
/// axes) so a sketch can be rendered at any size.
class Stroke {
  const Stroke({required this.color, required this.width, required this.points});

  final Color color;

  /// Width relative to the canvas width.
  final double width;
  final List<Offset> points;
}

class Sketch {
  const Sketch(this.strokes);

  static const empty = Sketch([]);

  final List<Stroke> strokes;

  bool get isEmpty => strokes.isEmpty;
}

/// A drawn character that is part of the server's gacha pool.
class CharacterCard {
  const CharacterCard({
    required this.id,
    required this.subject,
    required this.title,
    required this.rarity,
    required this.prompt,
    required this.artist,
    required this.sketch,
    this.day = 0,
    this.theme,
  });

  final String id;

  /// The player the drawing depicts.
  final String subject;
  final String title;
  final Rarity rarity;
  final String prompt;

  /// The player who drew it.
  final String artist;
  final Sketch sketch;

  /// The day the card was added to the pool (0 = initial setup).
  final int day;

  /// The theme of the prompt a challenger was drawn from.
  final DailyTheme? theme;

  /// Scenery to show the character in.
  DailyTheme get scenery => theme ?? DailyTheme.forest;
}
