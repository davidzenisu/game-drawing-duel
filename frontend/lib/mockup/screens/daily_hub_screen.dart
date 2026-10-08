import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../logic/game_controller.dart';
import '../logic/models.dart';
import '../widgets/card_art.dart';
import '../widgets/themed_background.dart';
import '../widgets/ticket_chip.dart';
import 'collection_screen.dart';
import 'drawing_screen.dart';
import 'duel_screen.dart';
import 'gacha_screen.dart';

/// The daily routine: draw a challenger, pull, fight and upgrade.
class DailyHubScreen extends StatefulWidget {
  const DailyHubScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<DailyHubScreen> createState() => _DailyHubScreenState();
}

class _DailyHubScreenState extends State<DailyHubScreen> {
  GameController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_controller.gacha.totalPulls == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLaunchBonus());
    }
  }

  void _showLaunchBonus() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.celebration_rounded),
        title: const Text('The server is live!'),
        content: Text(
          'All ${_controller.pool.length} characters are in the pool. '
          'Here are ${GameController.launchBonus} pulls to get you started.',
        ),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Let's go"))],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _drawChallenger() async {
    final result = await Navigator.of(context).push<DrawingResult>(
      MaterialPageRoute(
        builder: (_) => DrawingScreen(
          subject: _controller.challengerSubject.name,
          prompt: "Today's challenger",
          hint: 'Draw them as ${_controller.theme.prompt}.',
          rarity: Rarity.hero,
          theme: _controller.theme,
          hurry: _controller.incomingHurry,
        ),
      ),
    );
    if (result == null) return;
    _controller.submitChallenger(result.sketch, result.title);
    _toast('Challenger added to the pool. +1 pull!');
  }

  Future<void> _sendHurry() async {
    final target = await showModalBottomSheet<Player>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Send a hurry'),
              subtitle: Text(
                'Costs ${GameController.hurryCost} pull. Their next drawing gets shorter, '
                'and they only find out while drawing.',
              ),
            ),
            for (final player in _controller.otherPlayers)
              ListTile(
                leading: CircleAvatar(child: Text(player.name.characters.first)),
                title: Text(player.name),
                enabled: !_controller.hurriedToday.contains(player.id),
                trailing: _controller.hurriedToday.contains(player.id)
                    ? const Icon(Icons.check_rounded)
                    : const Icon(Icons.bolt_rounded, color: AppPalette.hurry),
                onTap: () => Navigator.of(context).pop(player),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    _toast(
      _controller.sendHurry(target)
          ? '${target.name} will have to hurry. Shh!'
          : 'You need at least ${GameController.hurryCost} pull to send a hurry.',
    );
  }

  Future<void> _nextDay() async {
    if (!_controller.challengerDrawn) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Skip today?'),
          content: const Text("You haven't drawn today's challenger yet and will miss its pull."),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Stay')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Next day')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _controller.nextDay();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final theme = _controller.theme;
        final onScenery = theme.isDark ? Colors.white : Colors.black87;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: onScenery,
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text('Day ${_controller.day} · ${theme.label}', key: ValueKey(_controller.day)),
            ),
            actions: [
              TicketChip(tickets: _controller.tickets),
              const SizedBox(width: 12),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _nextDay,
            icon: const Icon(Icons.bedtime_rounded),
            label: const Text('Next day'),
          ),
          body: ThemedBackground(
            theme: theme,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ActionCard(
                            icon: Icons.brush_rounded,
                            title: "Draw today's challenger",
                            subtitle: _controller.challengerDrawn
                                ? 'Done for today. Your challenger joined the pool as a hero.'
                                : 'Draw ${_controller.challengerSubject.name} as ${theme.prompt}. '
                                      '★★★ · 2 min · +1 pull',
                            done: _controller.challengerDrawn,
                            onTap: _controller.challengerDrawn ? null : _drawChallenger,
                          ),
                          _ActionCard(
                            icon: Icons.auto_awesome_rounded,
                            title: 'Summon',
                            subtitle:
                                '${_controller.tickets} pulls available · ${_controller.pool.length} characters in the pool',
                            onTap: () => _open(GachaScreen(controller: _controller)),
                          ),
                          _ActionCard(
                            icon: Icons.sports_martial_arts_rounded,
                            title: "Duel today's challengers",
                            subtitle: _controller.collection.isEmpty
                                ? 'Summon a character first.'
                                : 'Won ${_controller.duelsWon} · Lost ${_controller.duelsLost}'
                                      '${_controller.duelRewardClaimed ? '' : ' · First win today: +1 pull'}',
                            onTap: _controller.collection.isEmpty
                                ? null
                                : () => _open(DuelScreen(controller: _controller)),
                          ),
                          _ActionCard(
                            icon: Icons.collections_rounded,
                            title: 'Collection',
                            subtitle:
                                '${_controller.collection.length} characters'
                                '${_controller.upgradesAvailable > 0 ? ' · ${_controller.upgradesAvailable} upgrades ready' : ''}',
                            badge: _controller.upgradesAvailable,
                            onTap: () => _open(CollectionScreen(controller: _controller)),
                          ),
                          _ActionCard(
                            icon: Icons.bolt_rounded,
                            title: 'Send a hurry',
                            subtitle: 'Cut a friend\'s drawing time as a surprise.',
                            onTap: _sendHurry,
                          ),
                          const SizedBox(height: 16),
                          _ChallengerParade(cards: _controller.todaysChallengers, textColor: onScenery),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.done = false,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool done;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surface.withValues(alpha: 0.92),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Badge(
          isLabelVisible: badge > 0,
          label: Text('$badge'),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => RotationTransition(turns: animation, child: child),
            child: Icon(
              done ? Icons.check_circle_rounded : icon,
              key: ValueKey(done),
              color: done ? AppPalette.victory : colors.primary,
              size: 32,
            ),
          ),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _ChallengerParade extends StatelessWidget {
  const _ChallengerParade({required this.cards, required this.textColor});

  final List<CharacterCard> cards;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's challengers",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: textColor, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final card = cards[index];
              return TweenAnimationBuilder<double>(
                key: ValueKey(card.id),
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 400 + index * 120),
                curve: Curves.easeOutBack,
                builder: (context, value, child) => Transform.translate(
                  offset: Offset(0, (1 - value) * 60),
                  child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                ),
                child: SizedBox(
                  width: 110,
                  child: Column(
                    children: [
                      Standee(card: card, width: 90),
                      const SizedBox(height: 4),
                      Nameplate(name: card.subject, title: card.title, compact: true),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
