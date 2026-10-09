import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/models.dart';
import '../rules/themes.dart';
import '../widgets/card_art.dart';
import '../widgets/sketch_canvas.dart';
import '../widgets/themed_background.dart';

class DrawingResult {
  const DrawingResult(this.sketch, this.title);

  final Sketch sketch;
  final String title;
}

/// Timed drawing of a single character. Pops with a [DrawingResult].
class DrawingScreen extends StatefulWidget {
  const DrawingScreen({
    super.key,
    required this.subject,
    required this.prompt,
    required this.hint,
    required this.rarity,
    this.initialTitle = '',
    this.titleLocked = false,
    this.reference,
    this.theme,
    this.hurry,
  });

  final String subject;
  final String prompt;
  final String hint;
  final Rarity rarity;
  final String initialTitle;

  /// The title was given by a prompt and can't be changed.
  final bool titleLocked;

  /// A drawing to build on, shown next to the canvas.
  final Sketch? reference;
  final DailyTheme? theme;

  /// A hurry another player bought, revealed only while drawing.
  final HurryPlan? hurry;

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> with SingleTickerProviderStateMixin {
  final _pad = SketchPadController();
  late final _title = TextEditingController(text: widget.initialTitle);
  final _stopwatch = Stopwatch();
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  Timer? _ticker;
  bool _hurried = false;
  bool _timeUp = false;

  Duration? get _limit => widget.rarity.drawTime;

  Duration get _remaining {
    final limit = _limit!;
    final cut = _hurried ? widget.hurry!.cut : Duration.zero;
    final left = limit - cut - _stopwatch.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void initState() {
    super.initState();
    _pad.addListener(_rebuild);
    _title.addListener(_rebuild);
    if (_limit != null) {
      _stopwatch.start();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    }
  }

  void _rebuild() => setState(() {});

  void _tick() {
    final hurry = widget.hurry;
    if (!_hurried && hurry != null && _stopwatch.elapsed >= _limit! * hurry.atFraction) {
      _hurried = true;
      _shake.forward(from: 0);
    }
    if (_remaining == Duration.zero) {
      _ticker?.cancel();
      _stopwatch.stop();
      _pad.lock();
      _timeUp = true;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _shake.dispose();
    _pad.dispose();
    _title.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_pad.isEmpty && _title.text.trim().isNotEmpty;

  void _submit() {
    _ticker?.cancel();
    Navigator.of(context).pop(DrawingResult(_pad.toSketch(), _title.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: _hurried ? _hurryBanner(context) : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 12),
                Expanded(child: _canvas()),
                const SizedBox(height: 12),
                _toolbar(context),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _title,
                        readOnly: widget.titleLocked,
                        maxLength: CharacterCard.maxTitleLength,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'e.g. The early years',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _canSubmit ? _submit : null,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text('Draw ${widget.subject}')),
      body: widget.theme == null ? body : ThemedBackground(theme: widget.theme!, child: body),
    );
  }

  Widget _header(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (widget.reference != null) ...[
              SizedBox(
                width: 56,
                child: Tooltip(
                  message: 'Your original drawing',
                  child: CardboardCard(child: SketchView(widget.reference!)),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StarRow(rarity: widget.rarity),
                  Text(widget.prompt, style: textTheme.titleMedium),
                  Text(widget.hint, style: textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _timer(context),
          ],
        ),
      ),
    );
  }

  Widget _timer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_limit == null) {
      return Chip(avatar: const Icon(Icons.all_inclusive_rounded), label: const Text('No limit'));
    }
    final remaining = _remaining;
    final urgent = remaining.inSeconds < 10;
    final total = _limit! - (_hurried ? widget.hurry!.cut : Duration.zero);
    final seconds = remaining.inMilliseconds / 1000;
    final label = '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) =>
          Transform.translate(offset: Offset(sin(_shake.value * pi * 10) * 8 * (1 - _shake.value), 0), child: child),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: total.inMilliseconds == 0 ? 0 : (seconds * 1000 / total.inMilliseconds).clamp(0.0, 1.0),
              strokeWidth: 6,
              color: urgent || _hurried ? AppPalette.hurry : colors.primary,
              backgroundColor: colors.surfaceContainerHighest,
            ),
            Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: urgent ? AppPalette.hurry : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hurryBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: AppPalette.hurry,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${widget.hurry!.by} bought a hurry! -${widget.hurry!.cut.inSeconds}s',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvas() {
    return Center(
      child: CardboardCard(
        child: Stack(
          fit: StackFit.expand,
          children: [
            SketchPad(controller: _pad),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _timeUp ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: const Center(
                    child: Text(
                      "Time's up!",
                      style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final brush in [...AppPalette.brushes, AppPalette.eraser])
          InkResponse(
            onTap: _pad.enabled ? () => _pad.setColor(brush) : null,
            radius: 20,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: brush,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _pad.color == brush ? colors.primary : colors.outlineVariant,
                  width: _pad.color == brush ? 3 : 1,
                ),
              ),
              child: brush == AppPalette.eraser ? const Icon(Icons.auto_fix_normal_rounded, size: 16) : null,
            ),
          ),
        const SizedBox(width: 8),
        for (final width in brushWidths)
          IconButton(
            isSelected: _pad.width == width,
            onPressed: _pad.enabled ? () => _pad.setWidth(width) : null,
            tooltip: 'Brush size',
            icon: Icon(Icons.circle, size: 6 + width * 400),
          ),
        IconButton(onPressed: _pad.enabled ? _pad.undo : null, tooltip: 'Undo', icon: const Icon(Icons.undo_rounded)),
        IconButton(
          onPressed: _pad.enabled ? _pad.clear : null,
          tooltip: 'Clear',
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}
