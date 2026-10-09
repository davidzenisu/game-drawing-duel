import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../widgets/game_action.dart';
import '../widgets/sign_out_button.dart';
import '../widgets/themed_background.dart';
import '../widgets/ticket_chip.dart';
import 'collection_screen.dart';
import 'drawing_screen.dart';
import 'fight_setup_screen.dart';
import 'gacha_screen.dart';
import 'prompt_screen.dart';
import 'results_screen.dart';
import 'vote_screen.dart';

/// The daily routine: draw a challenger, pull, fight and upgrade.
class DailyHubScreen extends StatefulWidget {
  const DailyHubScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<DailyHubScreen> createState() => _DailyHubScreenState();
}

class _DailyHubScreenState extends State<DailyHubScreen> {
  GameSession get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_controller.gachaStatus.totalPulls == 0) {
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
          'All ${_controller.pool.length} characters are in the pool.'
          '${_controller.tickets > 0 ? ' Here are ${_controller.tickets} pulls to get you started.' : ''}',
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
    final prompt = _controller.promptToDraw!;
    final result = await Navigator.of(context).push<DrawingResult>(
      MaterialPageRoute(
        builder: (_) => DrawingScreen(
          subject: prompt.subject.name,
          prompt: '"${prompt.title}"',
          hint: prompt.premade
              ? 'A premade prompt, as ${prompt.author.name} wrote none · ${prompt.theme.label}'
              : 'A challenger prompt by ${prompt.author.name} · ${prompt.theme.label}',
          rarity: Rarity.hero,
          initialTitle: prompt.title,
          titleLocked: true,
          theme: prompt.theme,
          hurry: _controller.incomingHurry,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (!await runGameAction(context, () => _controller.submitChallenger(result.sketch)) || !mounted) return;
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
              subtitle: Text('Free once a day. Their next drawing gets shorter, and they only find out while drawing.'),
            ),
            for (final player in _controller.otherPlayers)
              ListTile(
                leading: CircleAvatar(child: Text(player.name.characters.first)),
                title: Text(player.name),
                trailing: const Icon(Icons.bolt_rounded, color: AppPalette.hurry),
                onTap: () => Navigator.of(context).pop(player),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    final sent = await runGameQuery(context, () => _controller.sendHurry(target));
    if (sent == true && mounted) _toast('${target.name} will have to hurry. Shh!');
  }

  Future<void> _nextDay() async {
    if (_controller.hasOpenSteps) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Skip the rest of today?'),
          content: const Text("You haven't finished all of today's steps yet."),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Stay')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Next day')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await runGameAction(context, _controller.advanceDay);
  }

  /// Test sessions: you're done for today; the day moves on once everyone is.
  Future<void> _endDay() async {
    if (_controller.hasOpenSteps) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('End your day?'),
          content: const Text("You haven't finished all of today's steps yet."),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Stay')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('End my day')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await runGameAction(context, _controller.endDay);
  }

  /// Who ended today, in a test session.
  Widget _dayEndedCard() {
    final c = _controller;
    final ended = [
      for (final player in c.server.players)
        if (c.dayEnded.contains(player.id)) player.isYou ? 'you' : player.name,
    ];
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bedtime_rounded),
        title: Text(ended.isEmpty ? 'Nobody ended the day yet' : 'Ended today: ${ended.join(', ')}'),
        subtitle: const Text('The next day starts once everyone ended theirs.'),
        trailing: IconButton(
          onPressed: () => runGameAction(context, c.refreshDay),
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ),
    );
  }

  Future<void> _openStep(Widget screen) => Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => screen));

  String _unlocksOn(int step) => 'Starts on day $step of the loop.';

  List<Widget> _steps() {
    final c = _controller;
    final prompt = c.yourPrompt;
    final subject = c.promptSubject;
    final toDraw = c.promptToDraw;
    final fight = c.yourFight;
    final hasResults = c.yourFightResults.isNotEmpty || c.yourChallengerResults.isNotEmpty;
    return [
      _ActionCard(
        icon: Icons.edit_note_rounded,
        step: LoopStep.prompt,
        title: 'Write a challenger prompt',
        subtitle: prompt != null
            ? 'Sent: ${prompt.subject.name} · "${prompt.title}". Someone draws it tomorrow.'
            : subject == null
            ? "Today's prompt isn't ready yet."
            : 'Give ${subject.name} a challenger title for "${c.theme.label}".',
        done: prompt != null,
        onTap: prompt == null && subject != null ? () => _openStep(PromptScreen(controller: c)) : null,
      ),
      _ActionCard(
        icon: Icons.brush_rounded,
        step: LoopStep.draw,
        title: 'Draw a challenger',
        subtitle: !c.stepUnlocked(LoopStep.draw) || toDraw == null
            ? _unlocksOn(LoopStep.draw)
            : c.challengerDrawn
            ? 'Done. "${toDraw.title}" joined the pool as a hero.'
            : 'Draw ${toDraw.subject.name}: "${toDraw.title}" (prompt by ${toDraw.author.name}). ★★★ · 2 min · +1 pull',
        done: c.challengerDrawn,
        onTap: toDraw != null && !c.challengerDrawn ? _drawChallenger : null,
      ),
      _ActionCard(
        icon: Icons.groups_rounded,
        step: LoopStep.fight,
        title: 'Pick your fighters',
        subtitle: c.fightChallenger == null
            ? _unlocksOn(LoopStep.fight)
            : fight != null
            ? 'Locked in ${fight.fighters.length} fighters against ${fight.challenger.subject}.'
            : 'Send up to 4 fighters against a new challenger. The others vote tomorrow.',
        done: fight != null,
        onTap: c.fightChallenger == null ? null : () => _openStep(FightSetupScreen(controller: c)),
      ),
      _ActionCard(
        icon: Icons.how_to_vote_rounded,
        step: LoopStep.vote,
        title: 'Vote: who would win?',
        subtitle: !c.stepUnlocked(LoopStep.vote) || c.fightsToVote.isEmpty
            ? _unlocksOn(LoopStep.vote)
            : c.votesLeft == 0
            ? 'All ${c.fightsToVote.length} votes cast.'
            : '${c.votesLeft} of yesterday\'s fights waiting for your vote.',
        done: c.fightsToVote.isNotEmpty && c.votesLeft == 0,
        badge: c.votesLeft,
        onTap: c.fightsToVote.isEmpty ? null : () => _openStep(VoteScreen(controller: c)),
      ),
      _ActionCard(
        icon: Icons.sports_martial_arts_rounded,
        title: 'Battle results',
        subtitle: hasResults
            ? 'Watch the fights of your fighters and your challenger.'
            : 'Your first results arrive on day ${LoopStep.vote}.',
        onTap: hasResults ? () => _openStep(ResultsScreen(controller: c)) : null,
      ),
    ];
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
              if (_controller.canEndDay && _controller.canAdvanceDay)
                IconButton(
                  onPressed: _nextDay,
                  tooltip: 'Start the next day for everyone',
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              TicketChip(tickets: _controller.tickets),
              SignOutButton(session: _controller),
              const SizedBox(width: 12),
            ],
          ),
          floatingActionButton: _controller.canEndDay
              ? FloatingActionButton.extended(
                  onPressed: _controller.dayEnded.contains(_controller.you.id) ? null : _endDay,
                  icon: const Icon(Icons.bedtime_rounded),
                  label: Text(_controller.dayEnded.contains(_controller.you.id) ? 'Day ended' : 'End my day'),
                )
              : _controller.canAdvanceDay
              ? FloatingActionButton.extended(
                  onPressed: _nextDay,
                  icon: const Icon(Icons.bedtime_rounded),
                  label: const Text('Next day'),
                )
              : null,
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
                          if (_controller.canEndDay) _dayEndedCard(),
                          ..._steps(),
                          const SizedBox(height: 12),
                          _ActionCard(
                            icon: Icons.auto_awesome_rounded,
                            title: 'Summon',
                            subtitle:
                                '${_controller.tickets} pulls available · ${_controller.pool.length} characters in the pool',
                            onTap: () => _open(GachaScreen(controller: _controller)),
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
                            subtitle: _controller.hurrySentTo == null
                                ? "Free once a day: cut a friend's drawing time as a surprise."
                                : 'Sent to ${_controller.hurrySentTo!.name} today.',
                            done: _controller.hurrySentTo != null,
                            onTap: _controller.hurrySentTo == null ? _sendHurry : null,
                          ),
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
    this.step,
  });

  /// The step of the daily loop this card belongs to.
  final int? step;
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
        title: Text(step == null ? title : 'Step $step · $title'),
        subtitle: Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
