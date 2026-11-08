import 'package:flutter/material.dart';

import '../game/game_app.dart';
import '../theme/palette.dart';
import 'mock_game_session.dart';

/// The offline mockup inside the real app, for players who manage servers:
/// a fresh demo game under a bar to leave it. Its screens open in their own
/// navigator, so the bar stays on top; back goes back within the mockup
/// first. Nothing of it is kept once you leave.
class MockupShell extends StatefulWidget {
  const MockupShell({super.key});

  @override
  State<MockupShell> createState() => _MockupShellState();
}

class _MockupShellState extends State<MockupShell> {
  final _session = MockGameSession();
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The mockup's own screens make room for the keyboard; shrinking here
      // too would take its height away twice and leave them no room.
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Material(
            color: AppPalette.ticket,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.science_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Mockup: sample data, nothing is saved',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Exit'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            // The bar took the top inset.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: NavigatorPopHandler<Object?>(
                onPopWithResult: (_) => _navigator.currentState?.maybePop(),
                child: Navigator(
                  key: _navigator,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => GameRoot(session: _session)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
