import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game_session.dart';
import '../widgets/game_action.dart';

/// The admin form for gifting pulls and stars outside the regular rewards,
/// with a message (or just a message, with neither): to everyone on every
/// server, to everyone on one server, or to chosen players of one. They get
/// it on their notification board.
class SendGiftScreen extends StatefulWidget {
  const SendGiftScreen({super.key, required this.controller});

  final GameSession controller;

  /// The most pulls and stars one gift gives each player, as the API allows.
  static const maxPulls = 100;
  static const maxStars = 1000;

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
  final _stars = TextEditingController(text: '0');
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulls.addListener(_rebuild);
    _stars.addListener(_rebuild);
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
    _stars.dispose();
    _message.dispose();
    super.dispose();
  }

  GiftServer? get _server => _servers?.where((s) => s.code == _serverCode).firstOrNull;

  /// The number in [field], or null outside 0 to [max]. Empty counts as 0.
  static int? _count(TextEditingController field, int max) {
    final text = field.text.trim();
    final n = text.isEmpty ? 0 : int.tryParse(text);
    return n == null || n < 0 || n > max ? null : n;
  }

  int? get _pullCount => _count(_pulls, SendGiftScreen.maxPulls);
  int? get _starCount => _count(_stars, SendGiftScreen.maxStars);

  bool get _valid =>
      _pullCount != null &&
      _starCount != null &&
      _message.text.trim().isNotEmpty &&
      (_allServers || (_server != null && (_allPlayers || _positions.isNotEmpty)));

  Future<void> _send() async {
    final pulls = _pullCount;
    final stars = _starCount;
    if (pulls == null || stars == null || !_valid) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final sent = await runGameQuery(
      context,
      () => widget.controller.sendGift(
        message: _message.text.trim(),
        pulls: pulls,
        stars: stars,
        serverCode: _allServers ? null : _serverCode,
        positions: _allServers || _allPlayers ? null : (_positions.toList()..sort()),
      ),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Sent ${_what(pulls, stars)} to $sent ${sent == 1 ? 'player' : 'players'}.')),
    );
    Navigator.of(context).pop();
  }

  /// E.g. "2 pulls and 25 stars", "3 stars" or "a message".
  static String _what(int pulls, int stars) {
    final parts = [
      if (pulls > 0) '$pulls ${pulls == 1 ? 'pull' : 'pulls'}',
      if (stars > 0) '$stars ${stars == 1 ? 'star' : 'stars'}',
    ];
    return parts.isEmpty ? 'a message' : parts.join(' and ');
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
                  'Give pulls, stars or both outside the regular rewards, with a message; set both to 0 to send '
                  'just the message. Players see it on their notification board and get the pulls and stars once '
                  'they accept it.',
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pulls,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Pulls per player',
                          border: const OutlineInputBorder(),
                          errorText: _pullCount == null ? '0 to ${SendGiftScreen.maxPulls}' : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _stars,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Stars per player',
                          border: const OutlineInputBorder(),
                          errorText: _starCount == null ? '0 to ${SendGiftScreen.maxStars}' : null,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_pullCount == 0 && _starCount == 0) ...[
                  const SizedBox(height: 6),
                  Text('Neither pulls nor stars: just the message.', style: textTheme.bodySmall),
                ],
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
                  label: Text(_pullCount == 0 && _starCount == 0 ? 'Send message' : 'Send gift'),
                ),
              ],
            ),
    );
  }
}
