import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game_session.dart';
import '../rules/models.dart';
import '../rules/daily_loop.dart';
import '../rules/setup_plan.dart';
import '../widgets/admin_menu.dart';
import '../widgets/game_action.dart';
import '../widgets/account_menu.dart';

/// Join a server with a code (first: most players join one) or create one
/// with a prepopulated roster. New players get a short note on the game.
class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key, required this.controller});

  final GameSession controller;

  /// The intro note's key among the tutorials seen, once dismissed.
  static const introKey = 'servers-intro';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Hi ${controller.you.name}!'),
          actions: [
            AdminMenu(session: controller),
            AccountMenu(session: controller),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.login_rounded), text: 'Join server'),
              Tab(icon: Icon(Icons.add_circle_outline_rounded), text: 'Create server'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (controller.serverNotice case final notice?)
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(leading: const Icon(Icons.info_outline_rounded), title: Text(notice)),
              ),
            if (!controller.tutorialsSeen.contains(ServerScreen.introKey)) _IntroNote(controller: controller),
            Expanded(
              child: TabBarView(
                children: [
                  _JoinServer(controller: controller),
                  _CreateServer(controller: controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the game is about, in a sentence, for players who haven't joined or
/// created a server yet; gone for good once dismissed.
class _IntroNote extends StatelessWidget {
  const _IntroNote({required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.waving_hand_rounded, color: colors.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text:
                              'In Drawing Duel, you and your friends draw each other as heroes and challengers, '
                              'collect the drawings and send them into fights. ',
                        ),
                        TextSpan(
                          text: 'Everything is explained step by step once you join or create a server.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    style: textTheme.bodyMedium?.copyWith(color: colors.onPrimaryContainer),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => controller.markTutorialSeen(ServerScreen.introKey),
                child: const Text('Got it'),
              ),
            ),
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
  bool _speed = false;

  /// Your name on this server, when it isn't your account's.
  String? _yourName;
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

  Future<void> _renameYourself() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => RenameDialog(
        current: _yourName ?? widget.controller.accountName,
        title: 'Your name on this server',
        note: 'How the others see you on this server. Your account keeps its name.',
      ),
    );
    if (name != null && mounted) setState(() => _yourName = name);
  }

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
          'Everyone will draw characters of the others. Tap your name to go by another one here.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.star_rounded, size: 18),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_yourName ?? widget.controller.accountName} (you, admin)'),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_rounded, size: 16),
                ],
              ),
              tooltip: 'Change your name on this server',
              onPressed: _renameYourself,
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
              ? _PlanSummary(key: ValueKey((_playerCount, _speed)), playerCount: _playerCount, speed: _speed)
              : Text(
                  'You need between ${SetupPlan.minPlayers} and ${SetupPlan.maxPlayers} players.',
                  style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            const ButtonSegment(value: false, label: Text('Regular'), icon: Icon(Icons.calendar_month_rounded)),
            ButtonSegment(
              value: true,
              label: Text('Speed · ${SpeedMode.total.inMinutes} min'),
              icon: const Icon(Icons.bolt_rounded),
            ),
          ],
          selected: {_speed},
          onSelectionChanged: (selection) => setState(() => _speed = selection.single),
        ),
        const SizedBox(height: 8),
        Text(
          _speed
              ? 'A one-off session: everyone draws 2 characters, then ${SpeedMode.days.length} short days run '
                    'back to back on timers. A day ends early once everyone is done.'
              : 'One day of the game per real day, for as long as you like.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: valid
              ? () => runGameAction(
                  context,
                  () => widget.controller.createServer(_names, yourName: _yourName, speed: _speed),
                )
              : null,
          icon: const Icon(Icons.rocket_launch_rounded),
          label: const Text('Create server'),
        ),
      ],
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({super.key, required this.playerCount, required this.speed});

  final int playerCount;
  final bool speed;

  @override
  Widget build(BuildContext context) {
    final pool = SetupPlan.poolAtLaunch(playerCount, speed: speed);
    final total = pool.values.reduce((a, b) => a + b);
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$playerCount players · ${speed ? 2 : SetupPlan.drawingsPerPlayer(playerCount)} drawings each'),
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
  ServerSession? _preview;
  Player? _seat;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final preview = await runGameQuery(context, () => widget.controller.previewServer(_code.text));
    if (preview == null || !mounted) return;
    setState(() {
      _preview = preview;
      // The admin usually knows your name already.
      _seat = preview.players
          .where((p) => p.name == widget.controller.you.name && !preview.joined.contains(p.id))
          .firstOrNull;
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
          onChanged: (_) => setState(() => _preview = null),
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
          child: _preview == null
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
                          for (final (i, player) in _preview!.players.indexed)
                            RadioListTile<Player>(
                              value: player,
                              title: Text(player.name),
                              subtitle: i == 0
                                  ? const Text('Admin')
                                  : _preview!.joined.contains(player.id)
                                  ? const Text('Already joined')
                                  : null,
                              enabled: !_preview!.joined.contains(player.id),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _seat == null
                          ? null
                          : () => runGameAction(context, () => widget.controller.joinServer(_preview!, _seat!)),
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
