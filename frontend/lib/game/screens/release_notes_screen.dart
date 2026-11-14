import 'package:flutter/material.dart';

import '../release_notes.dart';
import '../widgets/game_action.dart';

/// What's new: the release notes, newest version first, each with its date
/// and what it added, changed, removed or fixed.
class ReleaseNotesScreen extends StatefulWidget {
  const ReleaseNotesScreen({super.key, this.load = loadReleaseNotes});

  /// Loads the notes; the bundled ones by default.
  final Future<List<Release>> Function() load;

  @override
  State<ReleaseNotesScreen> createState() => _ReleaseNotesScreenState();
}

class _ReleaseNotesScreenState extends State<ReleaseNotesScreen> {
  List<Release>? _releases;

  @override
  void initState() {
    super.initState();
    // Once built: errors show in a snack bar of the screen.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final releases = await runGameQuery(context, widget.load);
      if (mounted) setState(() => _releases = releases ?? const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final releases = _releases;
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: switch (releases) {
            null => const CircularProgressIndicator(),
            [] => const Padding(padding: EdgeInsets.all(24), child: Text('No release notes yet.')),
            _ => ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: releases.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _ReleaseCard(release: releases[i], latest: i == 0),
            ),
          },
        ),
      ),
    );
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// E.g. "14 November 2026".
String releaseDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

/// The notes' section names, as players read them.
String _sectionLabel(String title) => switch (title) {
  'Added' => 'New',
  _ => title,
};

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release, required this.latest});

  final Release release;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Version ${release.version}', style: textTheme.titleMedium),
                if (latest)
                  const Chip(
                    label: Text('Latest'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            Text(releaseDate(release.date), style: textTheme.bodySmall),
            for (final section in release.sections) ...[
              const SizedBox(height: 12),
              Text(
                _sectionLabel(section.title),
                style: textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 4),
              for (final item in section.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text.rich(_bold(item), style: textTheme.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// [text] with its `**bold**` parts in bold, as written in the notes.
TextSpan _bold(String text) {
  final parts = text.split('**');
  return TextSpan(
    children: [
      for (final (i, part) in parts.indexed)
        TextSpan(
          text: part,
          style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
    ],
  );
}
