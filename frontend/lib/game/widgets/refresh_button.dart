import 'package:flutter/material.dart';

import '../game_session.dart';
import 'game_action.dart';

/// App bar action to check on the server on demand: who joined or finished
/// their drawings, whether the game moved on or was cancelled. Spins while
/// it loads; errors show like any other action's.
class RefreshButton extends StatefulWidget {
  const RefreshButton({super.key, required this.session});

  final GameSession session;

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton> {
  bool _loading = false;

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await runGameAction(context, widget.session.refreshServer);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _loading ? null : _refresh,
      tooltip: 'Refresh',
      icon: _loading
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.refresh_rounded),
    );
  }
}

/// Under a "waiting" button: points to [RefreshButton], as the screen
/// doesn't update on its own.
class RefreshHint extends StatelessWidget {
  const RefreshHint({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Tap '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.refresh_rounded, size: (style?.fontSize ?? 12) + 4),
            ),
            const TextSpan(text: ' at the top to check on the others.'),
          ],
        ),
        style: style,
        textAlign: TextAlign.center,
      ),
    );
  }
}
