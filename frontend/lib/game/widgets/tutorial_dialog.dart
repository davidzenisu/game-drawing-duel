import 'package:flutter/material.dart';

import '../game_session.dart';
import '../tutorials.dart';

/// Shows [tutorial] unless [session] saw it already, and remembers it as
/// seen. Completes once it's closed.
Future<void> showTutorialOnce(BuildContext context, GameSession session, Tutorial tutorial) async {
  if (session.tutorialsSeen.contains(tutorial.key)) return;
  // Marked right away, so it never shows twice, e.g. on a double tap.
  session.markTutorialSeen(tutorial.key);
  await showTutorial(context, tutorial);
}

/// Shows [tutorial], e.g. again from "How to play".
Future<void> showTutorial(BuildContext context, Tutorial tutorial) => showDialog<void>(
  context: context,
  builder: (_) => TutorialDialog(tutorial: tutorial),
);

/// The pages of a [Tutorial], one after another; skippable.
class TutorialDialog extends StatefulWidget {
  const TutorialDialog({super.key, required this.tutorial});

  final Tutorial tutorial;

  @override
  State<TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<TutorialDialog> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.tutorial.pages;
    final last = _page == pages.length - 1;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.tutorial.title, style: text.labelLarge?.copyWith(color: colors.primary)),
              Flexible(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (page) => setState(() => _page = page),
                  children: [
                    for (final page in pages)
                      SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          children: [
                            Icon(page.icon, size: 56, color: colors.primary),
                            const SizedBox(height: 12),
                            Text(page.title, style: text.titleLarge, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Text(page.text, style: text.bodyLarge, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 16 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? colors.primary : colors.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  if (!last) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Skip')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: last
                        ? () => Navigator.of(context).pop()
                        : () => _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                    child: Text(last ? 'Got it' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
