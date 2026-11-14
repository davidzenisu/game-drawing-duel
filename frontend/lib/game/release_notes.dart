import 'package:flutter/services.dart';

/// A version of the game in the release notes (`CHANGELOG.md` at the root
/// of the repository, bundled with the app).
class Release {
  const Release({required this.version, required this.date, required this.sections});

  /// E.g. "0.7.0", a semantic version.
  final String version;
  final DateTime date;

  /// E.g. "Added" with its items, in the order of the notes.
  final List<({String title, List<String> items})> sections;
}

/// Where the app bundles the release notes: the repository's own file.
const releaseNotesAsset = '../CHANGELOG.md';

List<Release>? _loaded;

/// The release notes in [bundle], or the app's own, loaded once.
Future<List<Release>> loadReleaseNotes([AssetBundle? bundle]) async {
  if (bundle != null) return _load(bundle);
  return _loaded ??= await _load(rootBundle);
}

Future<List<Release>> _load(AssetBundle bundle) async => parseReleaseNotes(await bundle.loadString(releaseNotesAsset));

/// Reads release notes in the "Keep a Changelog" style: a `## [x.y.z] -
/// yyyy-mm-dd` heading per version, `### Section` headings, and `- item`
/// bullets, which may wrap onto indented lines. Anything else is skipped.
List<Release> parseReleaseNotes(String markdown) {
  final releases = <Release>[];
  String? version;
  DateTime? date;
  var sections = <({String title, List<String> items})>[];
  List<String>? items;

  void finish() {
    if (version != null && date != null) {
      releases.add(Release(version: version, date: date, sections: sections));
    }
  }

  final heading = RegExp(r'^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})\s*$');
  for (final line in markdown.split('\n')) {
    if (heading.firstMatch(line) case final match?) {
      finish();
      version = match.group(1);
      date = DateTime.parse(match.group(2)!);
      sections = [];
      items = null;
    } else if (version == null) {
      continue;
    } else if (line.startsWith('### ')) {
      items = [];
      sections.add((title: line.substring(4).trim(), items: items));
    } else if (line.startsWith('- ') && items != null) {
      items.add(line.substring(2).trim());
    } else if (line.startsWith('  ') && line.trim().isNotEmpty && (items?.isNotEmpty ?? false)) {
      items!.last = '${items.last} ${line.trim()}';
    }
  }
  finish();
  return releases;
}
