import 'dart:async';

import 'package:flutter/material.dart';

import '../game_session.dart';
import 'game_action.dart';

/// Cancelling the server at any point of the game, e.g. when a player drops
/// out, from the account menu. Asks twice, as it ends the server for
/// everyone: the second time only after a countdown.
abstract final class CancelServer {
  /// Seconds to wait before the final confirmation can be given.
  static const countdownSeconds = 10;

  static Future<void> confirm(BuildContext context, GameSession session) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined),
        title: Text(session.server.isAdmin ? 'Cancel the server?' : 'Drop out of the server?'),
        content: const Text(
          'This cancels the server for everyone and deletes all drawings and '
          'everything played so far. Everyone goes back to creating or joining a server.',
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
    if (first != true || !context.mounted) return;
    final second = await showDialog<bool>(context: context, builder: (context) => const _FinalConfirmation());
    if (second == true && context.mounted) await runGameAction(context, session.cancelServer);
  }
}

/// The last chance to keep the server; confirming only unlocks after
/// [CancelServer.countdownSeconds].
class _FinalConfirmation extends StatefulWidget {
  const _FinalConfirmation();

  @override
  State<_FinalConfirmation> createState() => _FinalConfirmationState();
}

class _FinalConfirmationState extends State<_FinalConfirmation> {
  int _secondsLeft = CancelServer.countdownSeconds;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _secondsLeft--);
      if (_secondsLeft == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.warning_amber_rounded),
    title: const Text('Are you sure?'),
    content: const Text('The drawings are gone for good, this cannot be undone.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep playing')),
      FilledButton(
        onPressed: _secondsLeft > 0 ? null : () => Navigator.pop(context, true),
        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
        child: Text(_secondsLeft > 0 ? 'Cancel for everyone ($_secondsLeft)' : 'Cancel for everyone'),
      ),
    ],
  );
}
