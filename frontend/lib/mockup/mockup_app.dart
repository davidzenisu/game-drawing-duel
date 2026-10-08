import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'logic/game_controller.dart';
import 'screens/daily_hub_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/server_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/signup_screen.dart';

/// Entry point of the offline gameplay mockup, enabled through
/// `FeatureFlags.mockupGameplay`.
class MockupGameApp extends StatefulWidget {
  const MockupGameApp({super.key, this.controller});

  /// Optional controller, mainly for tests.
  final GameController? controller;

  @override
  State<MockupGameApp> createState() => _MockupGameAppState();
}

class _MockupGameAppState extends State<MockupGameApp> {
  late final GameController _controller = widget.controller ?? GameController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drawing Duel (Mockup)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: (context, child) => Banner(message: 'MOCKUP', location: BannerLocation.bottomStart, child: child!),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(animation), child: child),
          ),
          child: KeyedSubtree(key: ValueKey(_controller.phase), child: _screenFor(_controller.phase)),
        ),
      ),
    );
  }

  Widget _screenFor(GamePhase phase) => switch (phase) {
    GamePhase.signup => SignupScreen(controller: _controller),
    GamePhase.server => ServerScreen(controller: _controller),
    GamePhase.lobby => LobbyScreen(controller: _controller),
    GamePhase.setup => SetupScreen(controller: _controller),
    GamePhase.daily => DailyHubScreen(controller: _controller),
  };
}
