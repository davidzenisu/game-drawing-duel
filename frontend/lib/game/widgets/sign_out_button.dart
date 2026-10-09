import 'package:flutter/material.dart';

import '../game_session.dart';
import 'game_action.dart';

/// App bar action to sign out. Hidden in the mockup, which has no account.
class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    if (session.isMockup) return const SizedBox.shrink();
    return IconButton(
      onPressed: () => runGameAction(context, session.signOut),
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout_rounded),
    );
  }
}
