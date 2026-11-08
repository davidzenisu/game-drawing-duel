import 'dart:math';

import 'package:flutter/material.dart';

import '../../mockup/bot_artist.dart';
import '../../theme/palette.dart';
import '../rules/models.dart';
import '../rules/themes.dart';
import '../rules/upgrades.dart';
import '../widgets/card_art.dart';
import '../widgets/themed_background.dart';

/// The title screen the game opens on, while it loads: tap once to go in.
/// Until the game is [ready] (e.g. the backend answered), the button waits.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.ready, required this.onStart});

  final bool ready;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Anywhere on the screen does it once the game is ready.
        onTap: ready ? onStart : null,
        child: ThemedBackground(
          theme: DailyTheme.forest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _FloatingStandees(),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4))],
                          ),
                          child: Image.asset('assets/logo.png', width: 96, height: 96, semanticLabel: 'Logo'),
                        ),
                        const SizedBox(height: 24),
                        _Title(textTheme: textTheme),
                        const SizedBox(height: 40),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: FilledButton.icon(
                            key: ValueKey(ready),
                            onPressed: ready ? onStart : null,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                              textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              // Solid while it waits, so it reads on the scenery.
                              disabledBackgroundColor: Colors.white.withValues(alpha: 0.9),
                              disabledForegroundColor: AppPalette.ink.withValues(alpha: 0.7),
                            ),
                            icon: ready
                                ? const Icon(Icons.play_arrow_rounded)
                                : const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2.5),
                                  ),
                            label: Text(ready ? 'Tap to start' : 'Loading…'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sample standees of doodled characters floating on both sides of the
/// title, bobbing and swaying out of step. Still when the platform asks for
/// less motion.
class _FloatingStandees extends StatefulWidget {
  const _FloatingStandees();

  @override
  State<_FloatingStandees> createState() => _FloatingStandeesState();
}

class _FloatingStandeesState extends State<_FloatingStandees> with SingleTickerProviderStateMixin {
  late final _float = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  /// Where each one floats: its side, how far down the screen, its size,
  /// and its phase in the float.
  static const _spots = [
    (left: true, top: 0.12, width: 104.0, phase: 0.0),
    (left: false, top: 0.2, width: 92.0, phase: 0.35),
    (left: true, top: 0.6, width: 84.0, phase: 0.6),
    (left: false, top: 0.66, width: 110.0, phase: 0.85),
  ];

  static final List<CharacterCard> _cards = () {
    final bots = BotArtist(7);
    const rarities = [Rarity.legend, Rarity.hero, Rarity.adventurer, Rarity.hero];
    return [
      for (final (i, rarity) in rarities.indexed)
        CharacterCard(
          id: 'splash-$i',
          subject: '',
          title: '',
          rarity: rarity,
          prompt: rarity.label,
          artist: '',
          sketch: bots.doodle(rarity.label),
        ),
    ];
  }();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: _float,
            builder: (context, _) => Stack(
              children: [
                for (final (i, spot) in _spots.indexed)
                  () {
                    final t = (_float.value + spot.phase) * 2 * pi;
                    // Half off the edge on phones, further in on wide screens.
                    final inset = max(-spot.width * 0.35, (constraints.maxWidth - 900) / 4);
                    return Positioned(
                      top: spot.top * constraints.maxHeight + 14 * sin(t),
                      left: spot.left ? inset + 8 * cos(t) : null,
                      right: spot.left ? null : inset + 8 * cos(t),
                      child: Transform.rotate(
                        angle: (spot.left ? -0.12 : 0.12) + 0.06 * sin(t + 1),
                        child: Standee(
                          card: _cards[i],
                          width: spot.width,
                          effects: const [UpgradeEffect.shadow, UpgradeEffect.outline],
                        ),
                      ),
                    );
                  }(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "ovid's" over DRAWING DUEL, in the blue nameplate of the cards.
class _Title extends StatelessWidget {
  const _Title({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: "ovid's Drawing Duel",
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppPalette.nameplateTop, AppPalette.nameplateBottom],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.nameplateBorder, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "ovid's",
                style: textTheme.titleMedium?.copyWith(
                  color: AppPalette.nameplateText.withValues(alpha: 0.85),
                  fontStyle: FontStyle.italic,
                  letterSpacing: 1,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'DRAWING DUEL',
                  maxLines: 1,
                  style: textTheme.displaySmall?.copyWith(
                    color: AppPalette.nameplateText,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
