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

  /// While the title is being typed, the keyboard shrinks the canvas: a
  /// tap on it then only hides the keyboard, so no stroke is drawn by
  /// mistake.
  final _titleFocus = FocusNode();
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
    _titleFocus.addListener(_rebuild);
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
    _titleFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_pad.isEmpty && _title.text.trim().isNotEmpty;

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
                const SizedBox(height: 12),
                Expanded(child: _canvas()),
                const SizedBox(height: 12),
                _toolbar(context),
              ],
            ),
          ),
        ),
      ),
    );
    final locked = _locked;
    return PopScope(
      canPop: !locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _blockedBack();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Draw ${widget.subject}'), automaticallyImplyLeading: !locked),
        body: widget.theme == null ? body : ThemedBackground(theme: widget.theme!, child: body),
      ),
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
                  if (!widget.nameplate) StarRow(rarity: widget.rarity),
                  if (widget.description case final description?)
                    Text(description, style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                  if (widget.nameplate)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Nameplate(
                        name: widget.subject,
                        title: widget.initialTitle,
                        rarity: widget.rarity,
                        nameFirst: true,
                        compact: true,
                      ),
                    )
                  else
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
    final total = _limit! - _cut;
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
            if (_titleFocus.hasFocus)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _titleFocus.unfocus(),
                  onPanStart: (_) => _titleFocus.unfocus(),
                ),
              ),
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

  /// The tools, the title to type and Done, on a card of their own, so they
  /// read well on every day's scenery, in light and dark mode.
  Widget _toolbar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
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
                          color: _pad.color == brush ? colors.primary : colors.outline,
                          width: _pad.color == brush ? 3 : 1,
                        ),
                      ),
                      child: brush == AppPalette.eraser
                          ? const Icon(Icons.auto_fix_normal_rounded, size: 16, color: AppPalette.ink)
                          : null,
                    ),
                  ),
                const SizedBox(width: 8),
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
            const SizedBox(height: 6),
            Row(
              children: [
                // A title given by the prompt shows at the top already.
                if (widget.titleLocked)
                  const Spacer()
                else
                  Expanded(
                    child: TextField(
                      controller: _title,
                      focusNode: _titleFocus,
                      maxLength: CharacterCard.maxTitleLength,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'e.g. The early years',
                        border: OutlineInputBorder(),
                        isDense: true,
                        counterText: '',
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
