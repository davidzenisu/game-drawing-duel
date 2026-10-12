import 'models.dart';
import 'themes.dart';

/// The game content editors manage: the descriptions players choose a person
/// and write a title for, and the titles that stand in when nobody wrote one.
enum ContentKind {
  hints(path: 'hints', label: 'Descriptions', noun: 'description', maxLength: null),
  premadeTitles(
    path: 'premade-titles',
    label: 'Premade titles',
    noun: 'premade title',
    maxLength: CharacterCard.maxTitleLength,
  );

  const ContentKind({required this.path, required this.label, required this.noun, required this.maxLength});

  final String path;
  final String label;
  final String noun;
  final int? maxLength;
}

/// A description or premade title in use. It's used from the day after it
/// was added on.
class ContentEntry {
  const ContentEntry({required this.id, required this.theme, required this.text, required this.createdAt});

  final String id;
  final DailyTheme theme;
  final String text;
  final DateTime createdAt;
}

class ContentAddResult {
  const ContentAddResult({required this.added, required this.skipped});

  final List<ContentEntry> added;

  /// Left out: the theme had them already (ignoring case), or they came twice.
  final List<String> skipped;
}
