import 'package:flutter/material.dart';

import '../game_session.dart';

/// The days a character still rests after a fight, on its card in the
/// fighter picker and the collection: a moon and the number of days.
class RestBadge extends StatelessWidget {
  const RestBadge({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Resting, ${backIn(days)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: colors.inverseSurface, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bedtime_rounded, size: 12, color: colors.onInverseSurface),
            const SizedBox(width: 2),
            Text(
              '${days}d',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.onInverseSurface, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
