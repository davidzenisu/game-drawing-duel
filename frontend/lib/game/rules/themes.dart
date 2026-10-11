import 'dart:ui';

/// Daily prompt themes, shown as hand-drawn style backgrounds: one per
/// weekday from Monday to Sunday (UTC). The everyday ideas for each come with
/// the prompt hints and premade titles, see `docs/concept/themes.md`.
enum DailyTheme {
  forest(
    label: 'Enchanted Forest',
    skyTop: Color(0xFF9ED8C8),
    skyBottom: Color(0xFFF3E7B4),
    hills: [Color(0xFF6FA35A), Color(0xFF4E8A45), Color(0xFF2F6136)],
    accent: Color(0xFFC0622F),
  ),
  beach(
    label: 'Hot Sandy Beaches',
    skyTop: Color(0xFF6EC6F2),
    skyBottom: Color(0xFFFFF1C9),
    hills: [Color(0xFF7FD6E0), Color(0xFF3BA9C9), Color(0xFFF2D49B)],
    accent: Color(0xFFFF8A3D),
  ),
  volcano(
    label: 'Volcano Lair',
    skyTop: Color(0xFF3B1F2B),
    skyBottom: Color(0xFFE0663A),
    hills: [Color(0xFF6B2E2A), Color(0xFF4A2228), Color(0xFF26141A)],
    accent: Color(0xFFFFB627),
  ),
  snow(
    label: 'Frozen Peaks',
    skyTop: Color(0xFFAFC8F0),
    skyBottom: Color(0xFFF2F6FF),
    hills: [Color(0xFFDCE7F7), Color(0xFFB5C9E8), Color(0xFF8AA4CF)],
    accent: Color(0xFF52C7F2),
  ),
  jungle(
    label: 'Misty Jungle',
    skyTop: Color(0xFFB7D3C0),
    skyBottom: Color(0xFFE8F1E4),
    hills: [Color(0xFF4F9A63), Color(0xFF2E7A4C), Color(0xFF1B5236)],
    accent: Color(0xFFE85AAD),
  ),
  space(
    label: 'Outer Space',
    skyTop: Color(0xFF0B0C2A),
    skyBottom: Color(0xFF3A2A6E),
    hills: [Color(0xFF4B3C8C), Color(0xFF32286A), Color(0xFF1C1640)],
    accent: Color(0xFFB98CFF),
  ),
  castle(
    label: 'Royal Castle',
    skyTop: Color(0xFFF7B7A3),
    skyBottom: Color(0xFFFDE9D0),
    hills: [Color(0xFFB8A27A), Color(0xFF8F7B5A), Color(0xFF5E4F3A)],
    accent: Color(0xFF9A5CF5),
  );

  const DailyTheme({
    required this.label,
    required this.skyTop,
    required this.skyBottom,
    required this.hills,
    required this.accent,
  });

  /// The theme of a calendar day (UTC): Monday's is the forest.
  static DailyTheme ofDate(DateTime date) => values[date.weekday - DateTime.monday];

  final String label;
  final Color skyTop;
  final Color skyBottom;
  final List<Color> hills;
  final Color accent;

  bool get isDark => skyTop.computeLuminance() < 0.2;
}
