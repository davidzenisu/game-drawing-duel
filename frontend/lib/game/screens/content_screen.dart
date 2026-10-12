import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/content.dart';
import '../rules/themes.dart';
import '../widgets/game_action.dart';

/// For content editors: the descriptions players choose a person and write a
/// title for, and the premade titles, per theme. New ones are used from
/// tomorrow on, retired ones until the end of today.
class ContentScreen extends StatelessWidget {
  const ContentScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: ContentKind.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Game content'),
          bottom: TabBar(tabs: [for (final kind in ContentKind.values) Tab(text: kind.label)]),
        ),
        body: TabBarView(
          children: [for (final kind in ContentKind.values) _ContentTab(controller: controller, kind: kind)],
        ),
      ),
    );
  }
}

class _ContentTab extends StatefulWidget {
  const _ContentTab({required this.controller, required this.kind});

  final GameSession controller;
  final ContentKind kind;

  @override
  State<_ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends State<_ContentTab> with AutomaticKeepAliveClientMixin {
  DailyTheme _theme = DailyTheme.forest;
  List<ContentEntry>? _entries;
  final _input = TextEditingController();
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// One per line, ignoring empty lines.
  List<String> get _texts => [
    for (final line in _input.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  String? get _tooLong {
    final max = widget.kind.maxLength;
    if (max == null) return null;
    final long = _texts.where((t) => t.length > max);
    return long.isEmpty ? null : 'At most $max characters per ${widget.kind.noun}';
  }

  Future<void> _load() async {
    setState(() => _entries = null);
    final theme = _theme;
    final entries = await runGameQuery(context, () => widget.controller.contentEntries(widget.kind, theme));
    if (!mounted || theme != _theme) return;
    setState(() => _entries = entries ?? const []);
  }

  Future<void> _add() async {
    final texts = _texts;
    setState(() => _busy = true);
    final result = await runGameQuery(context, () => widget.controller.addContent(widget.kind, _theme, texts));
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) return;
    _input.clear();
    final skipped = result.skipped.isEmpty ? '' : ', ${result.skipped.length} already there';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${result.added.length}$skipped. New ones are used from tomorrow on.')),
    );
    await _load();
  }

  Future<void> _retire(ContentEntry entry) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Retire this ${widget.kind.noun}?'),
        content: Text('"${entry.text}"\n\nIt is still used for the rest of today.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Retire')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (await runGameAction(context, () => widget.controller.retireContent(widget.kind, entry))) await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final entries = _entries;
    final tooLong = _tooLong;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final theme in DailyTheme.values)
                  ChoiceChip(
                    label: Text(theme.label),
                    selected: theme == _theme,
                    onSelected: (_) {
                      if (theme == _theme) return;
                      setState(() => _theme = theme);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              minLines: 2,
              maxLines: 6,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'New ${widget.kind.label.toLowerCase()} for ${_theme.label}',
                helperText: 'One per line. Ones the theme has already are skipped.',
                errorText: tooLong,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy || _texts.isEmpty || tooLong != null ? null : _add,
                icon: const Icon(Icons.add_rounded),
                label: Text(_texts.length > 1 ? 'Add ${_texts.length}' : 'Add'),
              ),
            ),
            const SizedBox(height: 16),
            if (entries == null)
              const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              )
            else if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No ${widget.kind.label.toLowerCase()} for ${_theme.label} yet.',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              Text('${entries.length} in use', style: Theme.of(context).textTheme.titleSmall),
              for (final entry in entries)
                ListTile(
                  title: Text(entry.text),
                  trailing: IconButton(
                    tooltip: 'Retire',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _retire(entry),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
