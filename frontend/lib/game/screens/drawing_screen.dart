import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../rules/themes.dart';
import '../widgets/card_art.dart';
import '../widgets/sketch_canvas.dart';
import '../widgets/themed_background.dart';
import '../../platform/leave_guard.dart';

class DrawingResult {
  const DrawingResult(this.sketch, this.title, {this.hurriedBy = const []});

  final Sketch sketch;
  final String title;

  /// Who sent a hurry against this drawing, in the order they hit.
  final List<String> hurriedBy;
}

/// Timed drawing of a single character. Pops with a [DrawingResult].
class DrawingScreen extends StatefulWidget {
  const DrawingScreen({
    super.key,
    required this.subject,
    required this.prompt,
    required this.hint,
    required this.rarity,
    this.description,
    this.initialTitle = '',
    this.titleLocked = false,
    this.reference,
    this.theme,
    this.timeLimit,
    this.hurries = const [],
    this.noBackingOut = false,
    this.nameplate = false,
  });

  final String subject;
  final String prompt;
  final String hint;
  final Rarity rarity;

  /// The description the prompt was written for, e.g. "Who is a sauna
  /// regular?", shown above it.
  final String? description;
  final String initialTitle;

  /// The title was given by a prompt and can't be changed.
  final bool titleLocked;

  /// A drawing to build on, shown next to the canvas.
  final Sketch? reference;
  final DailyTheme? theme;

  /// Overrides the [rarity]'s drawing time, e.g. for challengers.
  final Duration? timeLimit;

  /// Hurries other players sent, revealed only while drawing as they hit.
  final List<HurryPlan> hurries;

  /// Once the timer runs, there's no leaving before the drawing is done, so
  /// it can't be started over: no back button, and on the web the browser
  /// asks before the page is closed or reloaded. If time runs out with
  /// nothing drawn, leaving is allowed again.
  final bool noBackingOut;

  /// Shows [subject] and the [initialTitle] in a compact blue nameplate, as
  /// the character will appear, instead of the [prompt] text.
  final bool nameplate;

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> with SingleTickerProviderStateMixin {
  final _pad = SketchPadController();
  late final _title = TextEditingController(text: widget.initialTitle);
  // From `clock`, so tests can control the time.
  final _stopwatch = clock.stopwatch();
  late final AnimationController _shake;
  Timer? _ticker;
  bool _timeUp = false;
  bool _done = false;
  final _leaveGuard = LeaveGuard();

  /// Whether leaving now would let the drawing be started over.
  bool get _locked => widget.noBackingOut && _limit != null && !_done && !(_timeUp && _pad.isEmpty);

  /// How many of the hurries hit so far, and the time they took away.
  int _hits = 0;
  Duration _cut = Duration.zero;

  /// When the last hurry hit; its banner shows for [_bannerTime].
  Duration? _hitAt;

  /// The first of the hurries that hit at [_hitAt].
  int _bannerFrom = 0;
  static const _bannerTime = Duration(seconds: 3);

  bool get _hurried => _hits > 0;

  bool get _showBanner => _hitAt != null && !_timeUp && _stopwatch.elapsed - _hitAt! < _bannerTime;

  Duration? get _limit => widget.timeLimit ?? widget.rarity.drawTime;

  Duration get _remaining {
    final left = _limit! - _cut - _stopwatch.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void initState() {
    super.initState();
    // Created up front: creating it lazily in dispose() would fail.
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _pad.addListener(_rebuild);
    _title.addListener(_rebuild);
    if (_limit != null) {
      _stopwatch.start();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    }
    if (_locked) _leaveGuard.enable();
  }

  void _rebuild() => setState(() {});

  void _tick() {
    // Each hurry takes away the same time when it hits; with many, several
    // can hit at once.
    final before = _hits;
    while (_hits < widget.hurries.length && _remaining <= widget.hurries[_hits].left) {
      _cut += Hurries.cut;
      _hits++;
    }
    if (_hits > before) {
      _bannerFrom = before;
      _hitAt = _stopwatch.elapsed;
      _shake.forward(from: 0);
    }
    if (_remaining == Duration.zero) {
      _ticker?.cancel();
      _stopwatch.stop();
      _pad.lock();
      _timeUp = true;
      if (!_locked) _leaveGuard.disable();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _leaveGuard.disable();
    _ticker?.cancel();
    _shake.dispose();
    _pad.dispose();
    _title.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_pad.isEmpty;

  /// Done: a title given by the prompt goes with it as is, otherwise it's
  /// asked for now, so typing it never takes room from the canvas.
  Future<void> _finish() async {
    if (!widget.titleLocked) {
      final title = await _askTitle();
      if (title == null || !mounted) return;
      _title.text = title;
    }
    _submit();
  }

  /// Asks for the drawing's title; null if they'd rather keep drawing.
  Future<String?> _askTitle() => showDialog<String>(
    context: context,
    builder: (_) => _TitleDialog(initial: _title.text),
  );

  void _submit() {
    _ticker?.cancel();
    _done = true;
    _leaveGuard.disable();
    Navigator.of(context).pop(
      DrawingResult(_pad.toSketch(), _title.text.trim(), hurriedBy: [for (final hurry in widget.hurries) hurry.by]),
    );
  }

  void _blockedBack() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text("The clock is running: finish your drawing and press Done. There's no starting over."),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    // No app bar: the top bar holds the way back, who to draw and the
    // clock, so the canvas gets all the height it can.
    final body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(context, locked),
                const SizedBox(height: 6),
                Expanded(child: _canvas()),
                const SizedBox(height: 6),
                _toolbar(context),
              ],
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _blockedBack();
      },
      child: Scaffold(
        body: widget.theme == null ? body : ThemedBackground(theme: widget.theme!, child: body),
      ),
    );
  }

  /// Back (unless there's no backing out), who and what to draw, more
  /// about the prompt behind a button, and the clock.
  Widget _topBar(BuildContext context, bool locked) {
    final textTheme = Theme.of(context).textTheme;
    final canLeave = !locked && (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
    final info = widget.nameplate || widget.description != null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.fromLTRB(canLeave ? 0 : 8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The question the prompt answers, in a small line across the
            // top, so it doesn't make the bar much taller.
            if (widget.nameplate && widget.description != null)
              Padding(
                padding: EdgeInsets.only(left: canLeave ? 8 : 0, bottom: 2),
                child: Text(
                  widget.description!,
                  style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Row(
              children: [
                if (canLeave) const BackButton(),
                if (widget.reference != null) ...[
                  SizedBox(
                    width: 40,
                    child: Tooltip(
                      message: 'Your original drawing',
                      child: CardboardCard(child: SketchView(widget.reference!)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: widget.nameplate
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Nameplate(
                            name: widget.subject,
                            title: widget.initialTitle,
                            rarity: widget.rarity,
                            nameFirst: true,
                            compact: true,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${widget.subject} · ${widget.prompt}',
                                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                StarRow(rarity: widget.rarity, size: 14),
                              ],
                            ),
                            Text(widget.hint, style: textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                ),
                if (info)
                  IconButton(
                    onPressed: _showInfo,
                    tooltip: 'About this prompt',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.info_outline_rounded),
                  ),
                const SizedBox(width: 4),
                _timer(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The prompt's question and where it's from, kept out of the way.
  void _showInfo() {
    final textTheme = Theme.of(context).textTheme;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.nameplate ? widget.subject : '${widget.subject} · ${widget.prompt}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.nameplate) Text(widget.initialTitle, style: textTheme.titleMedium),
            if (widget.description case final description?) ...[
              const SizedBox(height: 8),
              Text(description, style: textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 8),
            Text(widget.hint, style: textTheme.bodyMedium),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to drawing'))],
      ),
    );
  }

  Widget _timer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_limit == null) {
      return const Tooltip(
        message: 'No time limit',
        child: SizedBox.square(dimension: 48, child: Icon(Icons.all_inclusive_rounded)),
      );
    }
    final remaining = _remaining;
    final urgent = remaining.inSeconds < 10;
    final total = _limit! - _cut;
    final seconds = remaining.inMilliseconds / 1000;
    final label = '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) =>
          Transform.translate(offset: Offset(sin(_shake.value * pi * 10) * 8 * (1 - _shake.value), 0), child: child),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: total.inMilliseconds == 0 ? 0 : (seconds * 1000 / total.inMilliseconds).clamp(0.0, 1.0),
              strokeWidth: 5,
              color: urgent || _hurried ? AppPalette.hurry : colors.primary,
              backgroundColor: colors.surfaceContainerHighest,
            ),
            Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
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

  /// Floats over the top of the canvas, so the canvas never changes size,
  /// and lets the strokes through.
  Widget _hurryBanner(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: IgnorePointer(
        child: AnimatedSlide(
          offset: _showBanner ? Offset.zero : const Offset(0, -0.3),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: _showBanner ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: _hurried ? _hurryMessage() : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  /// E.g. "Alex sent a hurry! -5s" or "Alex, Sam and 2 more sent hurries! -20s".
  static String _hurryText(List<String> by) {
    final cut = '-${(Hurries.cut * by.length).inSeconds}s';
    return switch (by) {
      [final one] => '$one sent a hurry! $cut',
      [final a, final b] => '$a and $b sent hurries! $cut',
      [final a, final b, final c] => '$a, $b and $c sent hurries! $cut',
      [final a, final b, ...final rest] => '$a, $b and ${rest.length} more sent hurries! $cut',
      _ => '',
    };
  }

  Widget _hurryMessage() {
    return Material(
      elevation: 4,
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
                _hurryText([for (final h in widget.hurries.sublist(_bannerFrom, _hits)) h.by]),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
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
            _hurryBanner(context),
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

  /// The colours on one row, the other tools and Done on the next, on a
  /// card of their own, so they read well on every day's scenery, in light
  /// and dark mode. On narrow screens the rows shrink a little rather than
  /// wrap.
  Widget _toolbar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final brush in [...AppPalette.brushes, AppPalette.eraser])
                    InkResponse(
                      onTap: _pad.enabled ? () => _pad.setColor(brush) : null,
                      radius: 18,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: _swatch(colors, brush, size: 30, selected: _pad.color == brush),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final width in brushWidths) _widthButton(context, width),
                        IconButton(
                          onPressed: _pad.enabled ? _pad.undo : null,
                          tooltip: 'Undo',
                          icon: const Icon(Icons.undo_rounded),
                        ),
                        IconButton(
                          onPressed: _pad.enabled ? _pad.clear : null,
                          tooltip: 'Clear',
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _canSubmit ? _finish : null,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _swatch(ColorScheme colors, Color brush, {required double size, required bool selected}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brush,
        shape: BoxShape.circle,
        border: Border.all(color: selected ? colors.primary : colors.outline, width: selected ? 3 : 1),
      ),
      child: brush == AppPalette.eraser
          ? Icon(Icons.auto_fix_normal_rounded, size: size * 0.55, color: AppPalette.ink)
          : null,
    );
  }

  /// A brush width: a dot of that size, ringed when it's the one in use.
  Widget _widthButton(BuildContext context, double width) {
    final colors = Theme.of(context).colorScheme;
    final selected = _pad.width == width;
    return InkResponse(
      onTap: _pad.enabled ? () => _pad.setWidth(width) : null,
      radius: 22,
      child: Tooltip(
        message: 'Brush size',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? colors.primaryContainer : null,
            border: Border.all(color: selected ? colors.primary : Colors.transparent, width: 2),
          ),
          child: Center(
            child: Icon(
              Icons.circle,
              size: 6 + width * 400,
              color: selected ? colors.onPrimaryContainer : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a drawing's title once it's done, so typing it never takes
/// room from the canvas. Pops with the title, or null to keep drawing.
class _TitleDialog extends StatefulWidget {
  const _TitleDialog({required this.initial});

  final String initial;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _controller.text.trim();
    void save() => Navigator.of(context).pop(title);
    return AlertDialog(
      title: const Text('Name your drawing'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: CharacterCard.maxTitleLength,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => title.isEmpty ? null : save(),
        decoration: const InputDecoration(
          labelText: 'Title',
          hintText: 'e.g. The early years',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep drawing')),
        FilledButton(onPressed: title.isEmpty ? null : save, child: const Text('Save')),
      ],
    );
  }
}
