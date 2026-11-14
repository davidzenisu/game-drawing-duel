import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/release_notes.dart';
import 'package:frontend/game/screens/release_notes_screen.dart';
import 'package:frontend/game/widgets/account_menu.dart';
import 'package:frontend/mockup/mock_game_session.dart';

/// (major, minor, patch), to compare versions.
(int, int, int) _semver(String version) {
  final [major, minor, patch] = [for (final part in version.split('.')) int.parse(part)];
  return (major, minor, patch);
}

bool _newer((int, int, int) a, (int, int, int) b) =>
    a.$1 != b.$1 ? a.$1 > b.$1 : (a.$2 != b.$2 ? a.$2 > b.$2 : a.$3 > b.$3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the notes read versions, dates, sections and wrapped items', () {
    final releases = parseReleaseNotes('''
# Release notes

Intro text, skipped.

## [1.2.0] - 2026-11-14

### Added
- A **new** thing that wraps
  onto a second line.
- Another one.

### Fixed
- A bug.

## [1.1.3] - 2026-11-01

### Changed
- Something.
''');
    expect(
      [for (final r in releases) (r.version, r.date)],
      [('1.2.0', DateTime(2026, 11, 14)), ('1.1.3', DateTime(2026, 11, 1))],
    );
    final [added, fixed] = releases.first.sections;
    expect(added.title, 'Added');
    expect(added.items, ['A **new** thing that wraps onto a second line.', 'Another one.']);
    expect(fixed.title, 'Fixed');
    expect(fixed.items, ['A bug.']);
  });

  test("the repository's notes are bundled, newest first, and match the app's version", () async {
    final releases = await loadReleaseNotes(rootBundle);
    expect(releases, isNotEmpty);
    for (var i = 1; i < releases.length; i++) {
      final (newer, older) = (releases[i - 1], releases[i]);
      expect(_newer(_semver(newer.version), _semver(older.version)), isTrue, reason: newer.version);
      expect(newer.date.isBefore(older.date), isFalse, reason: newer.version);
      expect(newer.sections, isNotEmpty, reason: newer.version);
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final appVersion = RegExp(r'^version: (\d+\.\d+\.\d+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(releases.first.version, appVersion, reason: 'the latest notes are of this version');
  });

  testWidgets("What's new in the account menu shows the notes", (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    // Loaded for real once, outside the test's fake time; the screen then
    // gets them right away.
    final latest = (await tester.runAsync(loadReleaseNotes))!.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [AccountMenu(session: game)]),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("What's new"));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseNotesScreen), findsOneWidget);
    expect(find.text('Version ${latest.version}'), findsOneWidget);
    expect(find.text(releaseDate(latest.date)), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('New'), findsWidgets, reason: '"Added" as players read it');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
