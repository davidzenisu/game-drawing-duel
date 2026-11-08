import 'dart:math';

import 'package:flutter/material.dart';

import '../../mockup/bot_artist.dart';
import '../../theme/palette.dart';
import '../rules/models.dart';
import '../rules/themes.dart';
import '../rules/upgrades.dart';
import '../widgets/card_art.dart';
import '../widgets/themed_background.dart';

/// The title screen the game opens on, while it loads. The title and the
/// standees come in first, then the button fades in; it only goes into the
/// game once it's tapped and the game is [ready] (e.g. the backend
/// answered). Until then, a loading circle turns below it.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.ready, required this.onStart});

  final bool ready;
  final VoidCallback onStart;

  /// How long the title and the standees take to come in, the button last.
  static const intro = Duration(milliseconds: 2200);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: SplashScreen.intro);

  late final _title = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.45, curve: Curves.easeOutBack),
  );
  late final _standees = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.2, 0.75, curve: Curves.easeOutCubic),
  );
  late final _button = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.75, 1, curve: Curves.easeIn),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isDismissed) {
      // All at once when the platform asks for less motion.
      MediaQuery.of(context).disableAnimations ? _intro.value = 1 : _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: ThemedBackground(
        theme: DailyTheme.forest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _FloatingStandees(entrance: _standees),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The logo and the title drop in from above.
                      AnimatedBuilder(
                        animation: _title,
                        builder: (context, child) => Opacity(
                          opacity: _title.value.clamp(0.0, 1.0),
                          child: Transform.translate(offset: Offset(0, -160 * (1 - _title.value)), child: child),
                        ),
                        child: Column(
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      // Then the button fades in; it can't be tapped before.
                      AnimatedBuilder(
                        animation: _button,
                        builder: (context, child) => IgnorePointer(
                          ignoring: _intro.value < 1,
                          child: Opacity(opacity: _button.value, child: child),
                        ),
                        child: Column(
                          children: [
                            FilledButton.icon(
                              onPressed: widget.ready ? widget.onStart : null,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                                textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                // Solid while it waits, so it reads on the scenery.
                                disabledBackgroundColor: Colors.white.withValues(alpha: 0.9),
                                disabledForegroundColor: AppPalette.ink.withValues(alpha: 0.5),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Tap to start'),
                            ),
                            const SizedBox(height: 20),
                            // Turns until the button can be tapped.
                            SizedBox.square(
                              dimension: 32,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 300),
                                opacity: widget.ready ? 0 : 1,
                                child: widget.ready
                                    ? null
                                    : const CircularProgressIndicator(
                                        strokeWidth: 3.5,
                                        color: Colors.white,
                                        semanticsLabel: 'Loading',
                                      ),
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
          ],
        ),
      ),
    );
  }
}

/// Sample standees of doodled characters floating on both sides of the
/// title, bobbing and swaying out of step, after sliding in from the sides
/// with [entrance]. They don't float when the platform asks for less motion.
class _FloatingStandees extends StatefulWidget {
  const _FloatingStandees({required this.entrance});

  final Animation<double> entrance;

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
            animation: Listenable.merge([_float, widget.entrance]),
            builder: (context, _) => Stack(
              children: [
                for (final (i, spot) in _spots.indexed)
                  () {
                    final t = (_float.value + spot.phase) * 2 * pi;
                    // Half off the edge on phones, further in on wide screens.
                    final inset = max(-spot.width * 0.35, (constraints.maxWidth - 900) / 4);
                    // Slides in from beyond its edge, each a little later.
                    final come = Curves.easeOutCubic.transform(
                      ((widget.entrance.value - i * 0.12) / (1 - 3 * 0.12)).clamp(0.0, 1.0),
                    );
                    final away = (1 - come) * (inset + spot.width * 1.6);
                    return Positioned(
                      top: spot.top * constraints.maxHeight + 14 * sin(t),
                      left: spot.left ? inset + 8 * cos(t) - away : null,
                      right: spot.left ? null : inset + 8 * cos(t) - away,
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
