import 'setup_plan.dart';
import 'themes.dart';

/// A prompt hint in use: the description players choose a person and write
/// a title for, and the premade title that stands in if the player who got
/// it writes none. It's used from the day after it was added on.
class ContentEntry {
  const ContentEntry({
    required this.id,
    required this.theme,
    required this.text,
    required this.premadeTitle,
    required this.createdAt,
  });

  final String id;
  final DailyTheme theme;
  final String text;
  final String premadeTitle;
  final DateTime createdAt;
}

/// A description and its premade title to add.
class HintDraft {
  const HintDraft({required this.text, required this.premadeTitle});

  final String text;
  final String premadeTitle;
}

class ContentAddResult {
  const ContentAddResult({required this.added, required this.skipped});

  final List<ContentEntry> added;

  /// Descriptions left out: the theme had them already (ignoring case), or
  /// they came twice.
  final List<String> skipped;
}

/// A starter prompt in use: what a setup drawing of [prompt] shows of the
/// person drawn, e.g. "Them by night" for the alter. It's given out from the
/// next setup on.
class SetupHintEntry {
  const SetupHintEntry({required this.id, required this.prompt, required this.text, required this.createdAt});

  final String id;
  final SetupPrompt prompt;
  final String text;
  final DateTime createdAt;
}

class SetupHintAddResult {
  const SetupHintAddResult({required this.added, required this.skipped});

  final List<SetupHintEntry> added;

  /// Texts left out: the prompt type had them already (ignoring case), or
  /// they came twice.
  final List<String> skipped;
}
