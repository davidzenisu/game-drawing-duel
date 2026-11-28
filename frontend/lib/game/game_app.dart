import 'package:flutter/material.dart';

import '../platform/back_guard.dart';
import '../theme/app_theme.dart';
import 'game_session.dart';
import 'sound.dart';
import 'screens/daily_hub_screen.dart';
import 'screens/load_failed_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/server_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/signup_screen.dart';
import 'widgets/key_controls.dart';

/// The game for a [GameSession], e.g. the offline mockup enabled through
/// `FeatureFlags.mockupGameplay`. On the web, the browser's back button
/// goes back one screen like the app's own, and on the first screen asks
/// "Leave the game?" ([BackGuard]). On a computer, Esc goes back the same
/// way, without leaving the game ([EscapeGoesBack]).
class GameApp extends StatefulWidget {
  const GameApp({super.key, required this.session, this.splash = true, this.backGuard});

  final GameSession session;

  /// Whether the game opens on its title screen ([SplashScreen]).
  final bool splash;

  /// Catches the browser's back button, a [BackGuard] unless given.
  final BackGuard? backGuard;

  @override
  State<GameApp> createState() => _GameAppState();
}

class _GameAppState extends State<GameApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final _backGuard = widget.backGuard ?? BackGuard();
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _backGuard.start(_onBack);
    sound
      ..preload()
      ..startMusic();
  }

  Future<void> _onBack() async {
    final navigator = _navigator.currentState;
    if (navigator == null || await navigator.maybePop() || _asking || !navigator.mounted) return;
    _asking = true;
    final leave = await showDialog<bool>(
      context: navigator.context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the game?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Leave')),
        ],
      ),
    );
    _asking = false;
    if (leave == true) _backGuard.leave();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.session.isMockup ? 'Drawing Duel (Mockup)' : 'Drawing Duel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      navigatorKey: _navigator,
      builder: (context, child) => EscapeGoesBack(navigator: _navigator, child: child!),
      home: GameRoot(session: widget.session, splash: widget.splash),
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
    GamePhase.loadFailed => LoadFailedScreen(controller: session),
    GamePhase.signIn => SignInScreen(controller: session),
    GamePhase.signup => SignupScreen(controller: session),
    GamePhase.server => ServerScreen(controller: session),
    GamePhase.lobby => LobbyScreen(controller: session),
    GamePhase.setup => SetupScreen(controller: session),
    GamePhase.daily => DailyHubScreen(controller: session),
  };
}
