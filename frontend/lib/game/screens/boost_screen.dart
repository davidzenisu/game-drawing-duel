import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../platform/leave_guard.dart';
import '../../theme/palette.dart';
import '../rules/daily_loop.dart';
import '../game_session.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/themed_background.dart';

/// Step 3: spread your boost stars across a few of yesterday's challengers,
/// swiping freely between them. Drag a star from the tray at the bottom onto
/// the challenger in view, or down from a challenger to take it back; a tap
/// does the same. The stars are only saved with Done; leaving with changes
/// not saved asks first. Tomorrow they're fought; the stars you leave are
/// spread by chance once the day is over. Behind each one, the scenery it'll
/// be fought in.
class BoostScreen extends StatefulWidget {
  const BoostScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<BoostScreen> createState() => _BoostScreenState();
}

/// A star being dragged: from the tray (null) or from a challenger's id.
class _Star {
  const _Star(this.from);

  final String? from;
}

class _BoostScreenState extends State<BoostScreen> {
  final _pages = PageController(viewportFraction: 0.82);
  int _page = 0;
  bool _saving = false;
  final _leaveGuard = LeaveGuard();

  /// The stars by challenger as saved, and as you set them here.
  Map<String, int> get _saved => {
    for (final t in widget.controller.boostTargets)
      if (t.stars > 0) t.challenger.id: t.stars,
  };
  late Map<String, int> _draft = _saved;

  bool get _dirty => !mapEquals(_draft, _saved);

  @override
  void dispose() {
    _leaveGuard.disable();
    _pages.dispose();
    super.dispose();
  }

  /// Gives a challenger a star, or takes one back: only here, until Done.
  void _give(String challengerId, int change) {
    setState(() {
      final stars = (_draft[challengerId] ?? 0) + change;
      _draft = {..._draft, challengerId: stars}..removeWhere((_, n) => n <= 0);
    });
    // On the web, the browser asks before the page is closed with changes.
    _dirty ? _leaveGuard.enable() : _leaveGuard.disable();
  }

  int get _left => Boost.stars - _draft.values.fold(0, (sum, n) => sum + n);

  bool _canGive(BoostTarget target) => !_saving && _left > 0 && target.stars < Boost.maxPerChallenger;

  /// Saves the stars; completes with whether it worked.
  Future<bool> _save() async {
    if (!_dirty) return true;
    setState(() => _saving = true);
    final saved = await runGameAction(context, () => widget.controller.setBoosts(_draft));
    if (!mounted) return saved;
    setState(() => _saving = false);
    if (saved) _leaveGuard.disable();
    return saved;
  }

  Future<void> _done() async {
    if (await _save() && mounted) Navigator.of(context).pop(true);
  }

  /// Leaving with changes not saved: save them, drop them, or stay.
  Future<void> _confirmLeave() async {
    final choice = await showDialog<_Leave>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save your boosts?'),
        content: const Text("You moved stars but didn't save them. Unsaved boosts are lost when you leave."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(_Leave.discard), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep boosting')),
          FilledButton(onPressed: () => Navigator.of(context).pop(_Leave.save), child: const Text('Save')),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _Leave.save:
        await _done();
      case _Leave.discard:
        _leaveGuard.disable();
        setState(() => _draft = _saved);
        Navigator.of(context).pop(false);
      case null:
        break;
    }
  }

  void _goTo(int page) =>
      _pages.animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        // The challengers with the stars as set here.
        final targets = [
          for (final t in widget.controller.boostTargets)
            BoostTarget(challenger: t.challenger, stars: _draft[t.challenger.id] ?? 0),
        ];
        final current = targets[_page.clamp(0, targets.length - 1)];
        return PopScope(
          canPop: !_dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave();
          },
          child: Scaffold(
            appBar: AppBar(title: Text('Boost challengers ${_page + 1}/${targets.length}')),
            body: Column(
              children: [
                Expanded(
                  child: ThemedBackground(
                    theme: current.challenger.scenery,
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: targets.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) {
                        final target = targets[index];
                        return _ChallengerCard(
                          key: ValueKey(target.challenger.id),
                          target: target,
                          inView: index == _page,
                          canTake: !_saving,
                          willAccept: (star) => star.from == null && index == _page && _canGive(target),
                          onGive: () => _give(target.challenger.id, 1),
                          onTakeBack: () => _give(target.challenger.id, -1),
                        );
                      },
                    ),
                  ),
                ),
                _StarTray(
                  left: _left,
                  enabled: _canGive(current),
                  saving: _saving,
                  unsaved: _dirty,
                  onGive: () => _give(current.challenger.id, 1),
                  onTakeBack: (star) => _give(star.from!, -1),
                  onPrevious: _page > 0 ? () => _goTo(_page - 1) : null,
                  onNext: _page < targets.length - 1 ? () => _goTo(_page + 1) : null,
                  onDone: _saving ? null : _done,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _Leave { save, discard }

/// A challenger to boost, taking stars dropped on it while it's in view.
class _ChallengerCard extends StatelessWidget {
  const _ChallengerCard({
    super.key,
    required this.target,
    required this.inView,
    required this.canTake,
    required this.willAccept,
    required this.onGive,
    required this.onTakeBack,
  });

  final BoostTarget target;
  final bool inView;
  final bool canTake;
  final bool Function(_Star star) willAccept;
  final VoidCallback onGive;
  final VoidCallback onTakeBack;

  @override
  Widget build(BuildContext context) {
    final challenger = target.challenger;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return DragTarget<_Star>(
      onWillAcceptWithDetails: (details) => willAccept(details.data),
      onAcceptWithDetails: (_) => onGive(),
      builder: (context, candidates, _) {
        final hovered = candidates.isNotEmpty;
        // The whole page takes stars; the card wraps its content, so the
        // scenery shows around it.
        return AnimatedScale(
          scale: inView ? 1 : 0.9,
          duration: const Duration(milliseconds: 250),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hovered ? AppPalette.rarityHero : colors.outlineVariant,
                    width: hovered ? 3 : 1,
                  ),
                  boxShadow: [
                    if (hovered) BoxShadow(color: AppPalette.rarityHero.withValues(alpha: 0.4), blurRadius: 24),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Standee(card: challenger, width: 140),
                    const SizedBox(height: 8),
                    Text(challenger.subject, style: textTheme.titleLarge, textAlign: TextAlign.center),
                    Text(challenger.title, style: textTheme.titleMedium, textAlign: TextAlign.center),
                    Text('Drawn by ${challenger.artist}', style: textTheme.bodySmall),
                    const SizedBox(height: 12),
                    // The challenger's own stars, always there.
                    Semantics(
                      label: '${Stars.challengerBase} stars of its own',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < Stars.challengerBase; i++) _star(color: AppPalette.rarityLegend),
                        ],
                      ),
                    ),
                    // The boost stars you gave it, below.
                    SizedBox(
                      height: _starSize,
                      child: target.stars == 0
                          ? Center(
                              child: Text(
                                'Drop a boost star here',
                                style: textTheme.bodySmall?.copyWith(color: colors.outline),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var slot = 0; slot < target.stars; slot++)
                                  _GivenStar(
                                    key: ValueKey('${challenger.id}-$slot'),
                                    from: challenger.id,
                                    enabled: canTake && inView,
                                    onTap: onTakeBack,
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

const _starSize = 40.0;

Widget _star({double size = _starSize, Color color = AppPalette.rarityHero}) =>
    Icon(Icons.star_rounded, size: size, color: color);

/// A star you gave, dragged down (or tapped) to take it back. It pops in.
class _GivenStar extends StatelessWidget {
  const _GivenStar({super.key, required this.from, required this.enabled, required this.onTap});

  final String from;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final star = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: _star(),
    );
    return Tooltip(
      message: 'Take a star back',
      child: InkResponse(
        onTap: enabled ? onTap : null,
        child: Draggable<_Star>(
          data: _Star(from),
          // Sideways drags swipe between the challengers.
          affinity: Axis.vertical,
          maxSimultaneousDrags: enabled ? 1 : 0,
          feedback: _star(size: _starSize * 1.3),
          childWhenDragging: Opacity(opacity: 0.3, child: _star()),
          child: star,
        ),
      ),
    );
  }
}

/// The stars left to give, at the bottom: drag one onto the challenger in
/// view, or tap it. Stars dragged down from a challenger land back here.
class _StarTray extends StatelessWidget {
  const _StarTray({
    required this.left,
    required this.enabled,
    required this.saving,
    required this.unsaved,
    required this.onGive,
    required this.onTakeBack,
    required this.onPrevious,
    required this.onNext,
    required this.onDone,
  });

  final int left;
  final bool enabled;
  final bool saving;

  /// Whether the stars moved here aren't saved yet: Done saves them.
  final bool unsaved;
  final VoidCallback? onDone;
  final VoidCallback onGive;
  final void Function(_Star star) onTakeBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return DragTarget<_Star>(
      onWillAcceptWithDetails: (details) => details.data.from != null && !saving,
      onAcceptWithDetails: (details) => onTakeBack(details.data),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? colors.primaryContainer : colors.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  left == 0
                      ? 'All ${Boost.stars} stars given. Drag one down to take it back.'
                      : 'Drag a star onto a challenger: $left of ${Boost.stars} left',
                  style: textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous challenger',
                      onPressed: onPrevious,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < Boost.stars; i++)
                            i < left
                                ? Tooltip(
                                    message: 'Give a star',
                                    child: InkResponse(
                                      onTap: enabled ? onGive : null,
                                      child: Draggable<_Star>(
                                        data: const _Star(null),
                                        maxSimultaneousDrags: enabled ? 1 : 0,
                                        feedback: _star(size: _starSize * 1.3),
                                        childWhenDragging: Opacity(opacity: 0.3, child: _star()),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: _star(color: enabled ? AppPalette.rarityHero : colors.outline),
                                        ),
                                      ),
                                    ),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Icon(Icons.star_outline_rounded, size: _starSize, color: colors.outline),
                                  ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next challenger',
                      onPressed: onNext,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                Text(
                  unsaved
                      ? 'Not saved yet: press Done to save your boosts.'
                      : 'Move them until the day is over; the ones you leave are spread by chance.',
                  style: textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onDone,
                    child: saving
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
