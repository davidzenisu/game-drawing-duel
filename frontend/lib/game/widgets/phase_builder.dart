import 'package:flutter/widgets.dart';

import '../game_session.dart';

/// Rebuilds with the session while it is in [phase], then keeps showing the
/// last build: a screen fading out after the phase changed (e.g. the server
/// was cancelled) must not read state that no longer exists.
class PhaseBuilder extends StatefulWidget {
  const PhaseBuilder({super.key, required this.session, required this.phase, required this.builder});

  final GameSession session;
  final GamePhase phase;
  final WidgetBuilder builder;

  @override
  State<PhaseBuilder> createState() => _PhaseBuilderState();
}

class _PhaseBuilderState extends State<PhaseBuilder> {
  Widget? _last;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      if (widget.session.phase == widget.phase || _last == null) _last = widget.builder(context);
      return _last!;
    },
  );
}
