import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/themed_background.dart';

/// Step 1: choose the person who fits the day's description best and write a
/// challenger title for them.
class PromptScreen extends StatefulWidget {
  const PromptScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<PromptScreen> createState() => _PromptScreenState();
}

class _PromptScreenState extends State<PromptScreen> {
  final _title = TextEditingController();
  Player? _subject;

  bool get _ready => _subject != null && _title.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final sent = await runGameAction(context, () => widget.controller.submitPrompt(_title.text, _subject!));
    if (sent && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final subject = _subject;
    final theme = controller.promptTheme;
    final textTheme = Theme.of(context).textTheme;
    // An existing card of the person, for inspiration.
    final reference = subject == null ? null : controller.pool.where((c) => c.subject == subject.name).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a challenger')),
      body: ThemedBackground(
        theme: theme,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(theme.label, style: textTheme.labelLarge),
                      Text(switch (controller.promptHint) {
                        final hint? => 'Who is $hint?',
                        null => 'Who would make a good challenger?',
                      }, style: textTheme.headlineSmall),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final player in controller.promptCandidates)
                            ChoiceChip(
                              label: Text(player.name),
                              selected: player == subject,
                              onSelected: (_) => setState(() => _subject = player),
                            ),
                        ],
                      ),
                      if (reference != null) ...[
                        const SizedBox(height: 16),
                        Center(child: Standee(card: reference, width: 72)),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _title,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          labelText: 'Challenger title',
                          hintText: 'e.g. Hot sandy beaches',
                          helperText: 'Another player draws this challenger tomorrow.',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _ready ? _submit() : null,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Nameplate(
                          name: subject?.name ?? '…',
                          title: _title.text.trim().isEmpty ? '…' : _title.text.trim(),
                          nameFirst: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _ready ? _submit : null,
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Send prompt'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
