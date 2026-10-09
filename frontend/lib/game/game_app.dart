import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'game_session.dart';
import 'screens/daily_hub_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/server_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/signup_screen.dart';

/// The game for a [GameSession], e.g. the offline mockup enabled through
/// `FeatureFlags.mockupGameplay`.
class GameApp extends StatelessWidget {
  const GameApp({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: session.isMockup ? 'Drawing Duel (Mockup)' : 'Drawing Duel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(animation), child: child),
          ),
          child: KeyedSubtree(key: ValueKey(session.phase), child: _screenFor(session.phase)),
        ),
      ),
    );
  }

  Widget _screenFor(GamePhase phase) => switch (phase) {
    GamePhase.signup => SignupScreen(controller: session),
    GamePhase.server => ServerScreen(controller: session),
    GamePhase.lobby => LobbyScreen(controller: session),
    GamePhase.setup => SetupScreen(controller: session),
    GamePhase.daily => DailyHubScreen(controller: session),
  };
}
