import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';

/// A big menu button: an icon over a title. Greyed out without [onTap],
/// e.g. a step of the loop that doesn't start today; a check once [done].
/// Tapping one without [onTap] shows why it isn't available: [unavailable].
class HubTile extends StatelessWidget {
  const HubTile({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
    this.done = false,
    this.badge = 0,
    this.height = 136,
    this.unavailable,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool done;
  final int badge;
  final double height;

  /// Why the tile can't be tapped right now, shown when it's tapped anyway.
  final String? unavailable;

  @override
  Widget build(BuildContext context) {
    final tile = _tile(context);
    final reason = unavailable;
    if (onTap != null || reason == null) return tile;
    return Tooltip(
      message: reason,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      preferBelow: false,
      child: tile,
    );
  }

  Widget _tile(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final accent = done ? AppPalette.victory : colors.primary;
    final muted = !enabled && !done;
    return Semantics(
      button: true,
      enabled: enabled,
      label: title,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        // Opaque, so greyed out tiles don't let the scenery through.
        color: muted ? colors.surfaceContainerHighest : colors.surface,
        elevation: muted ? 0 : 1,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: muted ? 0.45 : 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Badge(
                      isLabelVisible: badge > 0,
                      label: Text('$badge'),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (child, animation) => RotationTransition(turns: animation, child: child),
                        child: Icon(
                          done ? Icons.check_circle_rounded : icon,
                          key: ValueKey(done),
                          size: 44,
                          color: muted ? colors.outline : accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The summon button: a glowing banner whose colors keep turning, with
/// sparkles drifting across and the pulls you have ready.
class SummonTile extends StatefulWidget {
  const SummonTile({super.key, required this.pulls, required this.onTap});

  final int pulls;
  final VoidCallback onTap;

  @override
  State<SummonTile> createState() => _SummonTileState();
}

class _SummonTileState extends State<SummonTile> with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(seconds: 4))
    ..repeat();

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.pulls > 0;
    return Semantics(
      button: true,
      label: 'Summon',
      child: AnimatedBuilder(
        animation: _shine,
        builder: (context, child) {
          final t = _shine.value;
          // Breathes a little while pulls are waiting.
          final pulse = ready ? 1 + 0.015 * sin(t * 4 * pi) : 1.0;
          return Transform.scale(
            scale: pulse,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: SweepGradient(
                  center: Alignment.centerLeft,
                  transform: GradientRotation(t * 2 * pi),
                  colors: const [
                    AppPalette.rarityHero,
                    AppPalette.brushPink,
                    AppPalette.rarityLegend,
                    AppPalette.ticket,
                    AppPalette.rarityHero,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.rarityLegend.withValues(alpha: ready ? 0.35 + 0.25 * sin(t * 2 * pi).abs() : 0.2),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onTap,
            child: SizedBox(
              height: 132,
              child: Stack(
                children: [
                  Positioned.fill(child: _Sparkles(animation: _shine)),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 52, color: Colors.white),
                        const SizedBox(height: 4),
                        Text(
                          'Summon',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            shadows: const [Shadow(color: Colors.black38, blurRadius: 6)],
                          ),
                        ),
                        if (ready)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${widget.pulls} ${widget.pulls == 1 ? 'pull' : 'pulls'} ready',
                              style: const TextStyle(color: AppPalette.ticket, fontWeight: FontWeight.w800),
                            ),
                          ),
                      ],
                    ),
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

/// Little stars drifting up across the summon button.
class _Sparkles extends StatelessWidget {
  const _Sparkles({required this.animation});

  final Animation<double> animation;

  static const _stars = [(0.08, 0.0), (0.22, 0.35), (0.4, 0.7), (0.62, 0.15), (0.78, 0.55), (0.92, 0.85)];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              for (final (x, phase) in _stars)
                () {
                  final p = (animation.value + phase) % 1;
                  return Positioned(
                    left: x * constraints.maxWidth,
                    top: (1 - p) * constraints.maxHeight - 8,
                    child: Opacity(
                      opacity: sin(p * pi).clamp(0, 1),
                      child: const Icon(Icons.star_rounded, size: 14, color: Colors.white),
                    ),
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiles two to a row, the last one alone if they don't add up.
class HubGrid extends StatelessWidget {
  const HubGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 12),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ],
            ),
          ),
      ],
    );
  }
}
