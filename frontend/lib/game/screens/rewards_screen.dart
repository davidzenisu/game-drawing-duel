import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/achievements.dart';
import '../widgets/game_action.dart';

/// Your achievements and their rewards, in the heroes menu: collecting
/// starter heroes and winning fights. A reached one has its stars for you
/// to collect, once.
class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key, required this.controller});

  final GameSession controller;

  /// Ready ones first, then the closest to done; collected ones last.
  static List<Achievement> _sorted(Iterable<Achievement> achievements) {
    int rank(Achievement a) => a.collectable ? 0 : (a.collected ? 2 : 1);
    return achievements.toList()..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : (b.progress / b.goal).compareTo(a.progress / a.goal);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final achievements = controller.achievements;
        bool aboutFights(Achievement a) => a.kind == AchievementKind.wins || a.kind == AchievementKind.streak;
        final sections = [
          (
            'Starter heroes',
            'Summon every starter hero of a player or a rarity.',
            _sorted(achievements.where((a) => !aboutFights(a))),
          ),
          ('Fights', 'Win the fights you pick the fighters for.', _sorted(achievements.where(aboutFights))),
        ];
        return Scaffold(
          appBar: AppBar(title: const Text('Rewards')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final (title, about, entries) in sections)
                if (entries.isNotEmpty)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                          ),
                          Text(about, style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 8),
                          for (final achievement in entries)
                            AchievementTile(
                              achievement: achievement,
                              onCollect: () => runGameAction(context, () => controller.collectAchievement(achievement)),
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// An achievement with your progress, its reward and, once reached, a
/// button to collect its stars.
class AchievementTile extends StatelessWidget {
  const AchievementTile({super.key, required this.achievement, required this.onCollect});

  final Achievement achievement;
  final VoidCallback onCollect;

  static IconData _icon(AchievementKind kind) => switch (kind) {
    AchievementKind.artist => Icons.brush_rounded,
    AchievementKind.portrait => Icons.portrait_rounded,
    AchievementKind.rarity => Icons.auto_awesome_rounded,
    AchievementKind.wins => Icons.emoji_events_rounded,
    AchievementKind.streak => Icons.local_fire_department_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: a.done ? colors.primaryContainer : colors.surfaceContainerHighest,
              child: Icon(_icon(a.kind), color: a.done ? colors.onPrimaryContainer : colors.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: text.titleSmall),
                  Text(a.description, style: text.bodySmall),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: a.progress / a.goal, minHeight: 6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${a.progress}/${a.goal}', style: text.labelMedium),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (a.collectable)
              FilledButton.icon(
                onPressed: onCollect,
                icon: const Icon(Icons.star_rounded, color: AppPalette.star),
                label: Text('Collect ${a.stars}'),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.collected) Icon(Icons.check_circle_rounded, size: 18, color: colors.primary),
                  const SizedBox(width: 2),
                  const Icon(Icons.star_rounded, size: 18, color: AppPalette.star),
                  Text('${a.stars}', style: text.labelLarge),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
