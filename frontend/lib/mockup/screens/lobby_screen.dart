import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/game_controller.dart';
import '../logic/setup_plan.dart';

/// Waiting room showing the server code while friends join.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  Timer? _joinTimer;

  @override
  void initState() {
    super.initState();
    _joinTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (!widget.controller.simulateNextJoin()) timer.cancel();
    });
  }

  @override
  void dispose() {
    _joinTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final server = controller.server;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final drawings = SetupPlan.drawingsPerPlayer(server.players.length);
    return Scaffold(
      appBar: AppBar(title: const Text('Lobby')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card.filled(
                    color: colors.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text('Server code', style: textTheme.labelLarge),
                          const SizedBox(height: 4),
                          SelectableText(
                            server.code,
                            style: textTheme.displaySmall?.copyWith(fontFamily: 'monospace', letterSpacing: 10),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: server.code));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Share with friends'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Players ${server.joined.length}/${server.players.length}', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final player in server.players)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) => SizeTransition(
                        sizeFactor: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: server.joined.contains(player.id)
                          ? ListTile(
                              key: ValueKey('${player.id}-in'),
                              leading: CircleAvatar(child: Text(player.name.characters.first)),
                              title: Text(player.isYou ? '${player.name} (you)' : player.name),
                              trailing: Icon(Icons.check_circle_rounded, color: colors.primary),
                            )
                          : ListTile(
                              key: ValueKey('${player.id}-out'),
                              leading: const CircleAvatar(child: Icon(Icons.hourglass_empty_rounded, size: 18)),
                              title: Text(player.name, style: TextStyle(color: colors.outline)),
                              subtitle: const Text('Waiting to join…'),
                            ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Everyone draws $drawings characters of the other players to fill the gacha pool.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: server.everyoneJoined ? controller.startSetup : null,
                    icon: const Icon(Icons.draw_rounded),
                    label: Text(server.everyoneJoined ? 'Start drawing' : 'Waiting for everyone…'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
