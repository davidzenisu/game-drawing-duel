import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/themes.dart';
import '../widgets/game_action.dart';
import '../widgets/themed_background.dart';

/// Loading the player failed, e.g. offline or the server is down. You stay
/// signed in and try again; signing out is up to you.
class LoadFailedScreen extends StatelessWidget {
  const LoadFailedScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final problem = controller.loadProblem;
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
                      Icon(Icons.cloud_off_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 8),
                      Text('Couldn\'t load the game', style: textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(
                        'You\'re still signed in. Check your connection and try again.',
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
                        onPressed: () => runGameAction(context, controller.retryLoading),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => runGameAction(context, controller.signOut),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Sign out'),
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
