import 'package:flutter/material.dart';

import '../game_session.dart';
import '../screens/content_screen.dart';

/// App bar action to manage the game content, only for content editors.
class ContentEditorButton extends StatelessWidget {
  const ContentEditorButton({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    if (!session.canEditContent) return const SizedBox.shrink();
    return IconButton(
      onPressed: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ContentScreen(controller: session))),
      tooltip: 'Game content',
      icon: const Icon(Icons.edit_note_rounded),
    );
  }
}
