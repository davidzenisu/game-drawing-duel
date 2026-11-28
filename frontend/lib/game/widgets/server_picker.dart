import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/setup_plan.dart';
import 'game_action.dart';

/// Every server you're on ([GameSession.myServers]), to switch to another
/// one, with a dot on those that wait on you, and a way to create or join
/// another one.
abstract final class ServerPicker {
  static Future<void> show(BuildContext context, GameSession session) async {
    final picked = await showDialog<_Pick>(
      context: context,
      builder: (_) => _ServerPickerDialog(session: session),
    );
    if (picked == null || !context.mounted) return;
    await runGameAction(context, switch (picked) {
      _SwitchTo(:final code) => () => session.switchServer(code),
      _AddServer() => session.addServer,
    });
  }
}

sealed class _Pick {
  const _Pick();
}

final class _SwitchTo extends _Pick {
  const _SwitchTo(this.code);

  final String code;
}

final class _AddServer extends _Pick {
  const _AddServer();
}

class _ServerPickerDialog extends StatelessWidget {
  const _ServerPickerDialog({required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final current = session.server.code;
        final servers = session.myServers;
        return AlertDialog(
          title: const Text('Your servers'),
          contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
          content: SizedBox(
            width: 400,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in servers)
                  _ServerTile(
                    server: s,
                    current: s.code == current,
                    onTap: s.code == current ? null : () => Navigator.of(context).pop(_SwitchTo(s.code)),
                  ),
                if (session.atServerLimit)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      "You're on ${SetupPlan.maxServers} servers, the most at once. "
                      "Speed sessions don't count: you can still create or join those.",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).pop(const _AddServer()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create or join'),
            ),
          ],
        );
      },
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, required this.current, required this.onTap});

  final ServerSummary server;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind = server.isSpeed ? 'Speed session' : (server.isTest ? 'Test session' : null);
    final details = [
      ?kind,
      server.phase.label,
      '${server.playerCount} players',
      if (current) 'you are here',
    ].join(' · ');
    return ListTile(
      selected: current,
      leading: Icon(server.isSpeed ? Icons.bolt_rounded : Icons.dns_rounded),
      title: Text('Server ${server.code}'),
      subtitle: Text(details),
      trailing: server.waitingOnYou
          ? Chip(
              label: const Text('Your turn'),
              visualDensity: VisualDensity.compact,
              backgroundColor: colors.errorContainer,
              labelStyle: TextStyle(color: colors.onErrorContainer),
              side: BorderSide.none,
            )
          : (current ? const Icon(Icons.check_rounded) : null),
      onTap: onTap,
    );
  }
}
