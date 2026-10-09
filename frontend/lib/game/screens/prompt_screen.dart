import 'package:flutter/material.dart';

import '../game_session.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/themed_background.dart';

/// Step 1: write a title prompt for a challenger from a theme and a character.
class PromptScreen extends StatefulWidget {
  const PromptScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<PromptScreen> createState() => _PromptScreenState();
}

class _PromptScreenState extends State<PromptScreen> {
  final _title = TextEditingController();

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
    final sent = await runGameAction(context, () => widget.controller.submitPrompt(_title.text));
    if (sent && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final subject = controller.promptSubject!;
    final theme = controller.theme;
    final textTheme = Theme.of(context).textTheme;
    // An existing card of the character, for inspiration.
    final reference = controller.pool.where((c) => c.subject == subject.name).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Write a challenger prompt')),
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
                      Text('Theme', style: textTheme.labelLarge),
                      Text(theme.label, style: textTheme.headlineSmall),
                      Text('Think of ${theme.prompt}.', style: textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (reference != null) ...[Standee(card: reference, width: 72), const SizedBox(width: 16)],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Character', style: textTheme.labelLarge),
                                Text(subject.name, style: textTheme.headlineSmall),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                        onSubmitted: (_) => _title.text.trim().isEmpty ? null : _submit(),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Nameplate(
                          name: subject.name,
                          title: _title.text.trim().isEmpty ? '…' : _title.text.trim(),
                          nameFirst: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _title.text.trim().isEmpty ? null : _submit,
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
