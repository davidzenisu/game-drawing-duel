import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/models.dart';
import '../rules/themes.dart';
import '../widgets/card_art.dart';
import '../widgets/sketch_canvas.dart';
import '../widgets/themed_background.dart';
import 'drawing_screen.dart';

/// The challenger you just drew, all on one screen to share as a
/// screenshot: the drawing, its nameplate with the subject and title, and
/// every hurry sent against it.
class DrawingRecapScreen extends StatelessWidget {
  const DrawingRecapScreen({
    super.key,
    required this.subject,
    required this.result,
    this.theme,
    this.rarity = Rarity.hero,
  });

  final String subject;
  final DrawingResult result;
  final DailyTheme? theme;
  final Rarity rarity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final onScenery = theme?.isDark ?? false ? Colors.white : Colors.black87;
    final body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Challenger drawn!',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(color: onScenery, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                // The drawing takes whatever room is left, so it all fits.
                Expanded(
                  child: Center(child: CardboardCard(shadow: true, child: SketchView(result.sketch))),
                ),
                const SizedBox(height: 12),
                Nameplate(name: subject, title: result.title, rarity: rarity, nameFirst: true),
                const SizedBox(height: 12),
                _Hurries(hurries: result.hurries),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Done · +1 pull'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      body: theme == null ? body : ThemedBackground(theme: theme!, child: body),
    );
  }
}

/// Every hurry sent against the drawing, with the time it took away.
class _Hurries extends StatelessWidget {
  const _Hurries({required this.hurries});

  final List<HurryOutcome> hurries;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hit = hurries.where((h) => h.hit).toList();
    final lost = hit.fold(Duration.zero, (sum, h) => sum + h.cut!);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_rounded, color: AppPalette.hurry),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(switch (hurries.length) {
                    0 => 'Nobody hurried you today',
                    1 => '1 hurry',
                    final n => '$n hurries',
                  }, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (hit.isNotEmpty)
                  Text(
                    '-${lost.inSeconds}s in all',
                    style: textTheme.titleSmall?.copyWith(color: AppPalette.hurry, fontWeight: FontWeight.w800),
                  ),
              ],
            ),
            if (hurries.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final hurry in hurries)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: CircleAvatar(child: Text(hurry.by.characters.first)),
                      label: Text(hurry.hit ? '${hurry.by} -${hurry.cut!.inSeconds}s' : '${hurry.by} · too late'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
