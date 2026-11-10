import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';
import '../widgets/download_drawing_button.dart';
import '../widgets/game_action.dart';
import '../widgets/sketch_canvas.dart';
import 'fight_history_screen.dart';

/// Admin screen to look at any drawing of any server, picked by server, day
/// (or the initial setup) and drawing: shown as drawn, without upgrade
/// effects, with a download button. For players who manage servers.
class DrawingsScreen extends StatefulWidget {
  const DrawingsScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<DrawingsScreen> createState() => _DrawingsScreenState();
}

/// The day dropdown's value for the setup drawings, which have no day.
const _setup = 0;

class _DrawingsScreenState extends State<DrawingsScreen> {
  List<GiftServer>? _servers;
  String? _serverCode;

  /// The picked server's drawings, once loaded.
  List<AdminDrawing>? _drawings;
  int? _day;
  AdminDrawing? _drawing;
  Sketch? _sketch;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadServers());
  }

  Future<void> _loadServers() async {
    setState(() => _loading = true);
    final servers = await runGameQuery(context, widget.controller.giftServers);
    if (!mounted) return;
    setState(() {
      _servers = servers ?? const [];
      _loading = false;
    });
  }

  Future<void> _pickServer(String? code) async {
    setState(() {
      _serverCode = code;
      _drawings = null;
      _day = null;
      _drawing = null;
      _sketch = null;
      _loading = code != null;
    });
    if (code == null) return;
    final drawings = await runGameQuery(context, () => widget.controller.serverDrawings(code));
    if (!mounted || code != _serverCode) return;
    setState(() {
      _drawings = drawings ?? const [];
      _loading = false;
    });
  }

  void _pickDay(int? day) => setState(() {
    _day = day;
    _drawing = null;
    _sketch = null;
  });

  Future<void> _pickDrawing(String? id) async {
    final drawing = _drawings?.where((d) => d.id == id).firstOrNull;
    setState(() {
      _drawing = drawing;
      _sketch = null;
      _loading = drawing != null;
    });
    if (drawing == null) return;
    final sketch = await runGameQuery(context, () => widget.controller.drawingSketch(drawing));
    if (!mounted || drawing != _drawing) return;
    setState(() {
      _sketch = sketch;
      _loading = false;
    });
  }

  /// The days with drawings, setup first.
  List<({int value, String label})> get _days {
    final drawings = _drawings ?? const <AdminDrawing>[];
    final seen = <int>{};
    return [
      for (final d in drawings)
        if (seen.add(d.day ?? _setup))
          (
            value: d.day ?? _setup,
            label: switch (d) {
              AdminDrawing(day: null) => 'Setup (initial drawings)',
              AdminDrawing(:final day?, :final date?) => 'Day $day · ${fightDate(date)}',
              AdminDrawing(:final day?) => 'Day $day',
            },
          ),
    ];
  }

  List<AdminDrawing> get _dayDrawings => [
    for (final d in _drawings ?? const <AdminDrawing>[])
      if ((d.day ?? _setup) == _day) d,
  ];

  @override
  Widget build(BuildContext context) {
    final servers = _servers ?? const <GiftServer>[];
    final drawings = _drawings;
    final days = _days;
    final drawing = _drawing;
    final sketch = _sketch;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drawings'),
        actions: [
          if (drawing != null && sketch != null)
            DownloadDrawingButton(sketch: sketch, subject: drawing.subject, title: drawing.title),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Every drawing of every server, as drawn: without upgrade effects.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_servers == null),
                    initialValue: _serverCode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Server', border: OutlineInputBorder()),
                    hint: Text(_servers == null ? 'Loading…' : (servers.isEmpty ? 'No servers' : 'Pick a server')),
                    items: [
                      for (final s in servers)
                        DropdownMenuItem(
                          value: s.code,
                          child: Text(
                            '${s.code}${s.speed ? ' (speed)' : ''} · ${s.players.map((p) => p.name).join(', ')}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _pickServer,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey(('day', _serverCode, drawings == null)),
                    initialValue: _day,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
                    hint: Text(switch (drawings) {
                      null => _serverCode == null ? 'Pick a server first' : 'Loading…',
                      [] => 'No drawings yet',
                      _ => 'Pick the setup or a day',
                    }),
                    items: [for (final d in days) DropdownMenuItem(value: d.value, child: Text(d.label))],
                    onChanged: days.isEmpty ? null : _pickDay,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(('drawing', _serverCode, _day)),
                    initialValue: drawing?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Drawing', border: OutlineInputBorder()),
                    hint: Text(_day == null ? 'Pick a date first' : 'Pick a drawing'),
                    items: [
                      for (final d in _dayDrawings)
                        DropdownMenuItem(
                          value: d.id,
                          child: Text('${d.subject}: ${d.title} (by ${d.artist})', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _day == null ? null : _pickDrawing,
                  ),
                  const SizedBox(height: 24),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (drawing != null && sketch != null) ...[
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: CardboardCard(child: SketchView(sketch)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${drawing.subject}: ${drawing.title}',
                      style: textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${'★' * drawing.rarity.stars} ${drawing.rarity.label} · drawn by ${drawing.artist}',
                      style: textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
