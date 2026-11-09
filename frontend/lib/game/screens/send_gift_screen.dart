import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game_session.dart';
import '../widgets/game_action.dart';

/// The admin form for gifting pulls outside the regular rewards, with a
/// message: to everyone on every server, to everyone on one server, or to
/// chosen players of one. They get it on their notification board.
class SendGiftScreen extends StatefulWidget {
  const SendGiftScreen({super.key, required this.controller});

  final GameSession controller;

  /// The most pulls one gift gives each player, as the API allows.
  static const maxPulls = 100;

  @override
  State<SendGiftScreen> createState() => _SendGiftScreenState();
}

class _SendGiftScreenState extends State<SendGiftScreen> {
  List<GiftServer>? _servers;
  bool _loading = true;
  bool _sending = false;

  bool _allServers = true;
  String? _serverCode;
  bool _allPlayers = true;
  final Set<int> _positions = {};
  final _pulls = TextEditingController(text: '1');
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulls.addListener(_rebuild);
    _message.addListener(_rebuild);
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    final servers = await runGameQuery(context, widget.controller.giftServers);
    if (!mounted) return;
    setState(() {
      _servers = servers ?? const [];
      _loading = false;
    });
  }

  @override
  void dispose() {
    _pulls.dispose();
    _message.dispose();
    super.dispose();
  }

  GiftServer? get _server => _servers?.where((s) => s.code == _serverCode).firstOrNull;

  int? get _pullCount {
    final n = int.tryParse(_pulls.text.trim());
    return n == null || n < 1 || n > SendGiftScreen.maxPulls ? null : n;
  }

  bool get _valid =>
      _pullCount != null &&
      _message.text.trim().isNotEmpty &&
      (_allServers || (_server != null && (_allPlayers || _positions.isNotEmpty)));

  Future<void> _send() async {
    final pulls = _pullCount;
    if (pulls == null || !_valid) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final sent = await runGameQuery(
      context,
      () => widget.controller.sendGift(
        message: _message.text.trim(),
        pulls: pulls,
        serverCode: _allServers ? null : _serverCode,
        positions: _allServers || _allPlayers ? null : (_positions.toList()..sort()),
      ),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Sent $pulls ${pulls == 1 ? 'pull' : 'pulls'} to $sent ${sent == 1 ? 'player' : 'players'}.'),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final servers = _servers ?? const [];
    final server = _server;
    return Scaffold(
      appBar: AppBar(title: const Text('Send a gift')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Give pulls outside the regular rewards, with a message. Players see it on their notification '
                  'board and get the pulls once they accept it.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Send to all servers (and all players)'),
                  value: _allServers,
                  onChanged: (on) => setState(() => _allServers = on),
                ),
                if (!_allServers) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _serverCode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Server', border: OutlineInputBorder()),
                    hint: Text(servers.isEmpty ? 'No servers' : 'Pick a server'),
                    items: [
                      for (final s in servers)
                        DropdownMenuItem(
                          value: s.code,
                          child: Text(
                            '${s.code}${s.speed ? ' (speed)' : ''}${s.launched ? '' : ' (not launched)'} · '
                            '${s.players.map((p) => p.name).join(', ')}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (code) => setState(() {
                      _serverCode = code;
                      _positions.clear();
                    }),
                  ),
                  if (server != null) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send to all players of that server'),
                      value: _allPlayers,
                      onChanged: (on) => setState(() => _allPlayers = on),
                    ),
                    if (!_allPlayers) ...[
                      Text('Players', style: textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in server.players)
                            FilterChip(
                              label: Text(p.joined ? p.name : '${p.name} (not joined)'),
                              selected: _positions.contains(p.position),
                              onSelected: (on) =>
                                  setState(() => on ? _positions.add(p.position) : _positions.remove(p.position)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _pulls,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Pulls per player',
                    border: const OutlineInputBorder(),
                    errorText: _pullCount == null ? 'Between 1 and ${SendGiftScreen.maxPulls}' : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _message,
                  maxLength: 200,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'e.g. Sorry for the downtime yesterday!',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _valid && !_sending ? _send : null,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send gift'),
                ),
              ],
            ),
    );
  }
}
