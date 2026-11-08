import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'game_session.dart';
import 'screens/daily_hub_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/server_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/signup_screen.dart';

/// The game for a [GameSession], e.g. the offline mockup enabled through
/// `FeatureFlags.mockupGameplay`.
class GameApp extends StatelessWidget {
  const GameApp({super.key, required this.session, this.splash = true});

  final GameSession session;

  /// Whether the game opens on its title screen ([SplashScreen]).
  final bool splash;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: session.isMockup ? 'Drawing Duel (Mockup)' : 'Drawing Duel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: GameRoot(session: session, splash: splash),
    );
  }
}

/// The screen for [session]'s phase, switched with a fade as it changes.
/// With [splash], the title screen comes first, while the game loads, until
/// it's tapped. The mockup also runs in one inside the real app
/// (`MockupShell`).
class GameRoot extends StatefulWidget {
  const GameRoot({super.key, required this.session, this.splash = false});

  final GameSession session;
  final bool splash;

  @override
  State<GameRoot> createState() => _GameRootState();
}

class _GameRootState extends State<GameRoot> {
  late bool _onSplash = widget.splash;

  GameSession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(animation), child: child),
        ),
        child: _onSplash
            ? SplashScreen(
                key: const ValueKey('splash'),
                ready: session.phase != GamePhase.loading,
                onStart: () => setState(() => _onSplash = false),
              )
            : KeyedSubtree(key: ValueKey(session.phase), child: _screenFor(session.phase)),
      ),
    );
  }

  Widget _screenFor(GamePhase phase) => switch (phase) {
    GamePhase.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
    GamePhase.signIn => SignInScreen(controller: session),
    GamePhase.signup => SignupScreen(controller: session),
    GamePhase.server => ServerScreen(controller: session),
    GamePhase.lobby => LobbyScreen(controller: session),
    GamePhase.setup => SetupScreen(controller: session),
    GamePhase.daily => DailyHubScreen(controller: session),
  };
}
