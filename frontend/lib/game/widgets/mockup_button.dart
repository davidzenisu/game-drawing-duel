import 'package:flutter/material.dart';

import '../../mockup/mockup_shell.dart';
import '../game_session.dart';

/// App bar action to try the offline mockup, only for players who manage
/// servers.
class MockupButton extends StatelessWidget {
  const MockupButton({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    if (!session.canManageServers) return const SizedBox.shrink();
    return IconButton(
      onPressed: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const MockupShell())),
      tooltip: 'Try the mockup',
      icon: const Icon(Icons.science_rounded),
    );
  }
}
