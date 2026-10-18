import 'package:flutter/material.dart';

import '../tutorials.dart';
import '../widgets/tutorial_dialog.dart';

/// Every intro, to see again any time.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How to play')),
      body: ListView(
        children: [
          for (final tutorial in Tutorial.values)
            ListTile(
              leading: Icon(tutorial.icon),
              title: Text(tutorial.title),
              subtitle: Text(tutorial.pages.first.title),
              trailing: const Icon(Icons.play_circle_outline_rounded),
              onTap: () => showTutorial(context, tutorial),
            ),
        ],
      ),
    );
  }
}
