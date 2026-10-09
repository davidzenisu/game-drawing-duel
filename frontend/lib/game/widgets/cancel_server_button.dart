import 'package:flutter/material.dart';

import '../game_session.dart';
import 'game_action.dart';

/// App bar action to cancel the server before it launches, e.g. when a
/// player drops out. Asks first, as it ends the server for everyone.
class CancelServerButton extends StatelessWidget {
  const CancelServerButton({super.key, required this.session});

  final GameSession session;

  Future<void> _confirm(BuildContext context) async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined),
        title: Text(session.server.isAdmin ? 'Cancel the server?' : 'Drop out of the server?'),
        content: const Text(
          'This cancels the server for everyone and deletes all drawings. '
          'Everyone goes back to creating or joining a server.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep playing')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Cancel server'),
          ),
        ],
      ),
    );
    if (cancel == true && context.mounted) await runGameAction(context, session.cancelServer);
  }

  @override
  Widget build(BuildContext context) =>
      IconButton(onPressed: () => _confirm(context), tooltip: 'Cancel server', icon: const Icon(Icons.cancel_outlined));
}
