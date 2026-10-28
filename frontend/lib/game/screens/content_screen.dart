import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/content.dart';
import '../rules/models.dart';
import '../rules/setup_plan.dart';
import '../rules/themes.dart';
import '../widgets/game_action.dart';

/// For content editors: the prompt hints per theme, each a description
/// players choose a person and write a title for, and the premade title that
/// stands in if the player who got it writes none. New ones are used from
/// tomorrow on, retired ones until the end of today.
///
/// And the starter prompts of the setup drawings per prompt type, given out
/// from the next setup on.
class ContentScreen extends StatefulWidget {
  const ContentScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

/// What the screen manages: the daily prompt hints or the starter prompts.
enum _Kind { daily, setup }

class _ContentScreenState extends State<ContentScreen> {
  _Kind _kind = _Kind.daily;
  DailyTheme _theme = DailyTheme.forest;
  List<ContentEntry>? _entries;
  final _description = TextEditingController();
  final _title = TextEditingController();
  bool _busy = false;

  SetupPrompt _prompt = SetupPrompt.basic;
  List<SetupHintEntry>? _setupEntries;
  final _starter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
    _title.addListener(() => setState(() {}));
    _starter.addListener(() => setState(() {}));
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _description.dispose();
    _title.dispose();
    _starter.dispose();
    super.dispose();
  }

  bool get _canAdd =>
      !_busy &&
      _description.text.trim().isNotEmpty &&
      _title.text.trim().isNotEmpty &&
      _title.text.trim().length <= CharacterCard.maxTitleLength;

  Future<void> _load() async {
    setState(() => _entries = null);
    final theme = _theme;
    final entries = await runGameQuery(context, () => widget.controller.contentEntries(theme));
    if (!mounted || theme != _theme) return;
    setState(() => _entries = entries ?? const []);
  }

  Future<void> _add() async {
    final draft = HintDraft(text: _description.text.trim(), premadeTitle: _title.text.trim());
    setState(() => _busy = true);
    final result = await runGameQuery(context, () => widget.controller.addContent(_theme, [draft]));
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) return;
    final message = result.added.isEmpty
        ? '${_theme.label} has this description already.'
        : 'Added. It is used from tomorrow on.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    if (result.added.isEmpty) return;
    _description.clear();
    _title.clear();
    await _load();
  }

  Future<void> _loadSetup() async {
    setState(() => _setupEntries = null);
    final prompt = _prompt;
    final entries = await runGameQuery(context, () => widget.controller.setupHints(prompt));
    if (!mounted || prompt != _prompt) return;
    setState(() => _setupEntries = entries ?? const []);
  }

  Future<void> _addSetup() async {
    final text = _starter.text.trim();
    setState(() => _busy = true);
    final result = await runGameQuery(context, () => widget.controller.addSetupHints(_prompt, [text]));
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) return;
    final message = result.added.isEmpty
        ? 'This type has this starter prompt already.'
        : 'Added. It is given out from the next setup on.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    if (result.added.isEmpty) return;
    _starter.clear();
    await _loadSetup();
  }

  Future<void> _retireSetup(SetupHintEntry entry) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retire this starter prompt?'),
        content: Text('"${entry.text}"\n\nSetups started from now on won\'t get it anymore.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Retire')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (await runGameAction(context, () => widget.controller.retireSetupHint(entry))) await _loadSetup();
  }

  void _switchTo(_Kind kind) {
    if (kind == _kind) return;
    setState(() => _kind = kind);
    kind == _Kind.daily ? _load() : _loadSetup();
  }

  Future<void> _retire(ContentEntry entry) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retire this prompt?'),
        content: Text('"${entry.text}" · ${entry.premadeTitle}\n\nIt is still used for the rest of today.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Retire')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (await runGameAction(context, () => widget.controller.retireContent(entry))) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Game content')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<_Kind>(
                segments: const [
                  ButtonSegment(value: _Kind.daily, label: Text('Daily prompts'), icon: Icon(Icons.today_rounded)),
                  ButtonSegment(value: _Kind.setup, label: Text('Setup'), icon: Icon(Icons.draw_rounded)),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) => _switchTo(selection.single),
              ),
              const SizedBox(height: 16),
              if (_kind == _Kind.setup)
                ..._setupSection(context)
              else ...[
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
                Text('New prompt for ${_theme.label}', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _description,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g. a challenger who burns dinner every night',
                    helperText: 'Players read it as "Who is …?"',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  enabled: !_busy,
                  maxLength: CharacterCard.maxTitleLength,
                  decoration: const InputDecoration(
                    labelText: 'Premade title',
                    hintText: 'e.g. Smoke Alarm Summoner',
                    helperText: 'Stands in if the player who gets it writes no title',
                    border: OutlineInputBorder(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _canAdd ? _add : null,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
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
                    child: Text('No prompts for ${_theme.label} yet.', textAlign: TextAlign.center),
                  )
                else ...[
                  Text('${entries.length} in use', style: textTheme.titleSmall),
                  for (final entry in entries)
                    ListTile(
                      title: Text(entry.text),
                      subtitle: Text(entry.premadeTitle),
                      trailing: IconButton(
                        tooltip: 'Retire',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _retire(entry),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _setupSection(BuildContext context) {
    final entries = _setupEntries;
    final textTheme = Theme.of(context).textTheme;
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final prompt in SetupPrompt.values)
            ChoiceChip(
              label: Text('${prompt.label} ${'★' * prompt.rarity.stars}'),
              selected: prompt == _prompt,
              onSelected: (_) {
                if (prompt == _prompt) return;
                setState(() => _prompt = prompt);
                _loadSetup();
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      Text('New starter prompt', style: textTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(
        controller: _starter,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: 'Starter prompt',
          hintText: 'e.g. Them by night',
          helperText: 'What the drawing shows of the person drawn',
          border: OutlineInputBorder(),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: !_busy && _starter.text.trim().isNotEmpty ? _addSetup : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add'),
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
          child: Text('No starter prompts for this type yet: it shows "${_prompt.hint}"', textAlign: TextAlign.center),
        )
      else ...[
        Text('${entries.length} in use', style: textTheme.titleSmall),
        for (final entry in entries)
          ListTile(
            title: Text(entry.text),
            trailing: IconButton(
              tooltip: 'Retire',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _retireSetup(entry),
            ),
          ),
      ],
    ];
  }
}
