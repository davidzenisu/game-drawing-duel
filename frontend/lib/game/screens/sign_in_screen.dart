import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/themes.dart';
import '../widgets/game_action.dart';
import '../widgets/themed_background.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final problem = controller.signInProblem;
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
                        'Sign in to play with your friends.',
                        style: textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      if (problem != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          problem,
                          style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => runGameAction(context, controller.signIn),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Sign in'),
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
