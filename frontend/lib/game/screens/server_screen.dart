import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game_session.dart';
import '../rules/models.dart';
import '../rules/setup_plan.dart';
import '../widgets/game_action.dart';

/// Create a server with a prepopulated roster or join one with a code.
class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Hi ${controller.you.name}!'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.add_circle_outline_rounded), text: 'Create server'),
              Tab(icon: Icon(Icons.login_rounded), text: 'Join server'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CreateServer(controller: controller),
            _JoinServer(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _CreateServer extends StatefulWidget {
  const _CreateServer({required this.controller});

  final GameSession controller;

  @override
  State<_CreateServer> createState() => _CreateServerState();
}

class _CreateServerState extends State<_CreateServer> {
  final _newName = TextEditingController();
  late final List<String> _names = widget.controller.suggestedPlayerNames
      .where((name) => name != widget.controller.you.name)
      .take(SetupPlan.minPlayers - 1)
      .toList();

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  int get _playerCount => _names.length + 1;

  void _add() {
    final name = _newName.text.trim();
    if (name.isEmpty || _playerCount >= SetupPlan.maxPlayers) return;
    setState(() {
      _names.add(name);
      _newName.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final valid = SetupPlan.supports(_playerCount);
    return _Constrained(
      children: [
        Text('Who is playing?', style: textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Prepopulate the full list of players (${SetupPlan.minPlayers}-${SetupPlan.maxPlayers}). '
          'Everyone will draw characters of the others.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.star_rounded, size: 18),
              label: Text('${widget.controller.you.name} (you, admin)'),
            ),
            for (final (i, name) in _names.indexed)
              InputChip(label: Text(name), onDeleted: () => setState(() => _names.removeAt(i))),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _newName,
          enabled: _playerCount < SetupPlan.maxPlayers,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Add a player',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(onPressed: _add, icon: const Icon(Icons.person_add_alt_1_rounded)),
          ),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: valid
              ? _PlanSummary(key: ValueKey(_playerCount), playerCount: _playerCount)
              : Text(
                  'You need between ${SetupPlan.minPlayers} and ${SetupPlan.maxPlayers} players.',
                  style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: valid ? () => runGameAction(context, () => widget.controller.createServer(_names)) : null,
          icon: const Icon(Icons.rocket_launch_rounded),
          label: const Text('Create server'),
        ),
      ],
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({super.key, required this.playerCount});

  final int playerCount;

  @override
  Widget build(BuildContext context) {
    final pool = SetupPlan.poolAtLaunch(playerCount);
    final total = pool.values.reduce((a, b) => a + b);
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$playerCount players · ${SetupPlan.drawingsPerPlayer(playerCount)} drawings each'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                for (final rarity in Rarity.values)
                  if (pool[rarity]! > 0) Text('${'★' * rarity.stars} ${pool[rarity]}'),
                Text('= $total characters at launch'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinServer extends StatefulWidget {
  const _JoinServer({required this.controller});

  final GameSession controller;

  @override
  State<_JoinServer> createState() => _JoinServerState();
}

class _JoinServerState extends State<_JoinServer> {
  final _code = TextEditingController();
  List<Player>? _roster;
  Player? _seat;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final roster = await runGameQuery(context, () => widget.controller.previewServer(_code.text));
    if (roster == null || !mounted) return;
    setState(() {
      _roster = roster;
      _seat = roster.where((p) => p.name == widget.controller.you.name).firstOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _Constrained(
      children: [
        Text('Got a code from a friend?', style: textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: textTheme.headlineSmall?.copyWith(letterSpacing: 8, fontFamily: 'monospace'),
          decoration: const InputDecoration(labelText: 'Server code', border: OutlineInputBorder()),
          onChanged: (_) => setState(() => _roster = null),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _code.text.length == 6 ? _lookUp : null,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Find server'),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: _roster == null
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Text('Which one are you?', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    RadioGroup<Player>(
                      groupValue: _seat,
                      onChanged: (seat) => setState(() => _seat = seat),
                      child: Column(
                        children: [
                          for (final (i, player) in _roster!.indexed)
                            RadioListTile<Player>(
                              value: player,
                              title: Text(player.name),
                              subtitle: i == 0 ? const Text('Admin') : null,
                              enabled: i != 0,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _seat == null
                          ? null
                          : () => runGameAction(
                              context,
                              () => widget.controller.joinServer(_code.text, _roster!, _seat!),
                            ),
                      icon: const Icon(Icons.group_add_rounded),
                      label: const Text('Join server'),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Constrained extends StatelessWidget {
  const _Constrained({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}
