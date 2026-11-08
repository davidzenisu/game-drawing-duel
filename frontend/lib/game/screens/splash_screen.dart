import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/themes.dart';
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
          child: SafeArea(
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
                            : const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        label: Text(ready ? 'Tap to start' : 'Loading…'),
                      ),
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
