import 'package:flutter/material.dart';

import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';
import '../widgets/sketch_canvas.dart';

/// A challenger of the week ranking: its drawing, big (tap it for full
/// screen), who drew it and wrote its prompt, who boosted it with how many
/// stars, and how its fight went.
class RankingDetailScreen extends StatelessWidget {
  const RankingDetailScreen({super.key, required this.entry});

  final RankedChallenger entry;

  static String _fight(ChallengerFight fight) =>
      "${fight.challengerWon ? 'Won' : 'Lost'} against ${fight.player.name}'s team of heroes";

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final textTheme = Theme.of(context).textTheme;
    final heroRarity = entry.heroRarity;
    final author = entry.promptAuthor;
    return Scaffold(
      appBar: AppBar(title: Text('#${entry.place} · ${card.subject}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => FullScreenDrawing(card: card)),
                    ),
                    child: Semantics(
                      button: true,
                      label: 'Show the drawing full screen',
                      child: CardboardCard(child: SketchView(card.sketch)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Nameplate(name: card.subject, title: card.title, rarity: card.rarity),
                  const SizedBox(height: 12),
                  Text(
                    heroRarity == null
                        ? '${entry.stars} ★ at the end of the week'
                        : 'Weekly hero (${heroRarity.label}) with ${entry.stars} ★',
                    style: textTheme.titleMedium?.copyWith(color: heroRarity?.color),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  _Detail(icon: Icons.brush_rounded, label: 'Drawn by', value: card.artist),
                  _Detail(
                    icon: Icons.edit_note_rounded,
                    label: 'Prompt by',
                    value: author == null
                        ? 'default'
                        : entry.defaultPrompt
                        ? '${author.name} (default)'
                        : author.name,
                  ),
                  _Detail(
                    icon: Icons.keyboard_double_arrow_up_rounded,
                    label: 'Boosted',
                    value: entry.boostStars == 0 ? 'not boosted' : '+${entry.boostStars} ★',
                    children: [
                      for (final boost in entry.boosts)
                        Text(
                          '${boost.booster.name}: +${boost.stars} ★${boost.byChance ? ' (default)' : ''}',
                          style: textTheme.bodyMedium,
                        ),
                    ],
                  ),
                  _Detail(
                    icon: Icons.sports_kabaddi_rounded,
                    label: 'Fight',
                    value: entry.foughtBy.isEmpty ? 'Not fought' : entry.foughtBy.map(_fight).join('\n'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line of the details: an icon, what it is, and its value, with more
/// lines below if any.
class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.label, required this.value, this.children = const []});

  final IconData icon;
  final String label;
  final String value;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.labelMedium),
                Text(value, style: textTheme.titleMedium),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A drawing filling the screen, to zoom into; tap or close to go back.
class FullScreenDrawing extends StatelessWidget {
  const FullScreenDrawing({super.key, required this.card});

  final CharacterCard card;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(card.title, overflow: TextOverflow.ellipsis),
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CardboardCard(child: SketchView(card.sketch)),
            ),
          ),
        ),
      ),
    );
  }
}
