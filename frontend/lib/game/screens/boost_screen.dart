import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/daily_loop.dart';
import '../game_session.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';

/// Step 3: spread your boost stars across a few of yesterday's challengers,
/// moving freely between them. Tomorrow they're fought; the stars you leave
/// are spread by chance once the day is over.
class BoostScreen extends StatefulWidget {
  const BoostScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<BoostScreen> createState() => _BoostScreenState();
}

class _BoostScreenState extends State<BoostScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _saving = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _give(BoostTarget target, int change) async {
    final stars = {
      for (final t in widget.controller.boostTargets)
        if (t.stars > 0) t.challenger.id: t.stars,
    };
    stars[target.challenger.id] = target.stars + change;
    setState(() => _saving = true);
    await runGameAction(context, () => widget.controller.setBoosts(stars));
    if (mounted) setState(() => _saving = false);
  }

  void _goTo(int page) =>
      _pages.animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final targets = widget.controller.boostTargets;
        final left = widget.controller.boostStarsLeft;
        final textTheme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: Text('Boost challengers ${_page + 1}/${targets.length}')),
          body: Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: ListTile(
                  leading: const Icon(Icons.keyboard_double_arrow_up_rounded, color: AppPalette.rarityHero),
                  title: Text(
                    '${'★' * left}${'☆' * (Boost.stars - left)}  $left of ${Boost.stars} stars left',
                    style: textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    'Up to ${Boost.maxPerChallenger} on one. Move them until the day is over; '
                    'the ones you leave are spread by chance.',
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: targets.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) {
                    final target = targets[index];
                    return _BoostPage(
                      key: ValueKey(target.challenger.id),
                      target: target,
                      onGive: !_saving && left > 0 && target.stars < Boost.maxPerChallenger
                          ? () => _give(target, 1)
                          : null,
                      onTakeBack: !_saving && target.stars > 0 ? () => _give(target, -1) : null,
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous challenger',
                        onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Done'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next challenger',
                        onPressed: _page < targets.length - 1 ? () => _goTo(_page + 1) : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
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

class _BoostPage extends StatelessWidget {
  const _BoostPage({super.key, required this.target, required this.onGive, required this.onTakeBack});

  final BoostTarget target;
  final VoidCallback? onGive;
  final VoidCallback? onTakeBack;

  @override
  Widget build(BuildContext context) {
    final challenger = target.challenger;
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Standee(card: challenger, width: 160),
              const SizedBox(height: 8),
              Text(challenger.subject, style: textTheme.titleLarge, textAlign: TextAlign.center),
              Text(challenger.title, style: textTheme.titleMedium, textAlign: TextAlign.center),
              Text('Drawn by ${challenger.artist}', style: textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.outlined(
                    tooltip: 'Take a star back',
                    onPressed: onTakeBack,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${'★' * target.stars}${'☆' * (Boost.maxPerChallenger - target.stars)}',
                    style: textTheme.headlineMedium?.copyWith(color: AppPalette.rarityHero),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filled(tooltip: 'Give a star', onPressed: onGive, icon: const Icon(Icons.add_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${Stars.challengerBase} ★ + ${target.stars} from you, and the boosts of others',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
