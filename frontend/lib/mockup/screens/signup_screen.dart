import 'package:flutter/material.dart';

import '../logic/game_controller.dart';
import '../logic/themes.dart';
import '../widgets/themed_background.dart';

/// Account creation: sign up and pick a first name.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _useSocialProfile() {
    // Stands in for the first name a social login would provide.
    _name.text = 'Alex';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canContinue = _name.text.trim().isNotEmpty;
    return Scaffold(
      body: ThemedBackground(
        theme: DailyTheme.forest,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.brush_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 8),
                      Text('Drawing Duel', style: textTheme.headlineMedium, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(
                        'Mockup mode: everything stays in this browser tab, the other players are simulated.',
                        style: textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _useSocialProfile,
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('Sign up with social login'),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                          helperText: 'This is how your friends will see you.',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => canContinue ? widget.controller.signUp(_name.text) : null,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: canContinue ? () => widget.controller.signUp(_name.text) : null,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Finish account'),
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
