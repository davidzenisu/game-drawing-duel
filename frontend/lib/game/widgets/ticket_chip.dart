import 'package:flutter/material.dart';

import '../../theme/palette.dart';

/// Shows the number of available gacha pulls and pops when it changes.
class TicketChip extends StatelessWidget {
  const TicketChip({super.key, required this.tickets});

  final int tickets;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.confirmation_number_rounded, color: AppPalette.ticket),
      label: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
          child: child,
        ),
        child: Text('$tickets pulls', key: ValueKey(tickets)),
      ),
    );
  }
}
