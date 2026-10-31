import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../tutorials.dart';
import '../widgets/cancel_server_button.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/content_editor_button.dart';
import '../widgets/sign_out_button.dart';
import '../widgets/sketch_canvas.dart';
import '../widgets/themed_background.dart';
import '../widgets/tutorial_dialog.dart';
import '../widgets/ticket_chip.dart';
import 'boost_screen.dart';
import 'challengers_screen.dart';
import 'collection_screen.dart';
import 'drawing_screen.dart';
import 'fight_setup_screen.dart';
import 'gacha_screen.dart';
import 'how_to_play_screen.dart';
import 'prompt_screen.dart';
import 'ranking_screen.dart';
import 'results_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
  }

  /// The welcome intro the first time, then the launch bonus.
  Future<void> _greet() async {
    if (!mounted) return;
    await showTutorialOnce(context, _controller, Tutorial.welcome);
    if (_controller.gachaStatus.totalPulls == 0) _showLaunchBonus();
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

  /// Opens [screen], after [intro] the first time.
  Future<void> _open(Widget screen, [Tutorial? intro]) async {
    if (intro != null) await showTutorialOnce(context, _controller, intro);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _drawChallenger() async {
    await showTutorialOnce(context, _controller, Tutorial.draw);
    if (!mounted) return;
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
          description: prompt.question,
          initialTitle: prompt.title,
          titleLocked: true,
          theme: prompt.theme,
          timeLimit: challengerDrawTime,
          hurries: _controller.incomingHurries,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (!await runGameAction(context, () => _controller.submitChallenger(result.sketch)) || !mounted) return;
    _toast('Challenger drawn. +1 pull!');
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

  /// Opens a step's [screen], after [intro] the first time.
  Future<void> _openStep(Widget screen, Tutorial intro) async {
    await showTutorialOnce(context, _controller, intro);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => screen));
  }

  String _unlocksOn(int step) => 'Starts on day $step of the loop.';

  List<Widget> _steps() {
    final c = _controller;
    final prompt = c.yourPrompt;
    final toDraw = c.promptToDraw;
    final fight = c.yourFight;
    final hasResults = c.yourFightResults.isNotEmpty || c.yourChallengerResults.isNotEmpty;
    return [
      _ActionCard(
        icon: Icons.edit_note_rounded,
        step: LoopStep.prompt,
        title: 'Choose a challenger',
        subtitle: prompt != null
            ? 'Sent: ${prompt.subject.name} · "${prompt.title}". Someone draws it tomorrow.'
            : switch (c.promptHint) {
                final hint? => 'Who is $hint? Choose them and give them a title.',
                null => 'NO PROMPT',
              },
        done: prompt != null,
        onTap: prompt == null ? () => _openStep(PromptScreen(controller: c), Tutorial.prompt) : null,
      ),
      _ActionCard(
        icon: Icons.brush_rounded,
        step: LoopStep.draw,
        title: 'Draw a challenger',
        subtitle: !c.stepUnlocked(LoopStep.draw) || toDraw == null
            ? _unlocksOn(LoopStep.draw)
            : c.challengerDrawn
            ? 'Done. "${toDraw.title}" joined the challengers.'
            : [
                toDraw.question,
                'Draw ${toDraw.subject.name}: "${toDraw.title}" (prompt by ${toDraw.author.name}). ★★★ · 1:30 · +1 pull',
              ].nonNulls.join(' '),
        done: c.challengerDrawn,
        onTap: toDraw != null && !c.challengerDrawn ? _drawChallenger : null,
      ),
      _ActionCard(
        icon: Icons.keyboard_double_arrow_up_rounded,
        step: LoopStep.boost,
        title: 'Boost challengers',
        subtitle: !c.stepUnlocked(LoopStep.boost) || c.boostTargets.isEmpty
            ? _unlocksOn(LoopStep.boost)
            : c.canBoost
            ? 'Spread ${c.boostStarsLeft} of your ${Boost.stars} ★ across ${c.boostTargets.length} of '
                  'yesterday\'s challengers. They\'re fought tomorrow.'
            : 'All ${Boost.stars} ★ given. You can move them until the day is over.',
        done: c.boostTargets.isNotEmpty && !c.canBoost,
        badge: c.canBoost ? 1 : 0,
        onTap: c.boostTargets.isEmpty ? null : () => _openStep(BoostScreen(controller: c), Tutorial.boost),
      ),
      _ActionCard(
        icon: Icons.groups_rounded,
        step: LoopStep.fight,
        title: 'Pick your fighters',
        subtitle: c.fightChallenger == null
            ? _unlocksOn(LoopStep.fight)
            : fight != null
            ? '${fight.fightersWin ? 'Won' : 'Lost'} with ${fight.fighters.length} fighters against '
                  '${fight.challenger.subject}: ${fight.fighterStars} ★ vs. ${fight.challengerStars} ★'
                  '${fight.fightersWin ? '. +1 pull, +${fight.challengerStars} victory ★' : '.'}'
            : c.availableFighters.isEmpty
            ? 'All your characters fought this week. They\'re back on Monday.'
            : 'Beat a challenger\'s ${Stars.challengerBase} ★ and its secret boosts with up to 4 fighters. '
                  'A win earns a pull and its stars.',
        done: fight != null,
        onTap: c.fightChallenger == null || (fight == null && c.availableFighters.isEmpty)
            ? null
            : () => _openStep(FightSetupScreen(controller: c), Tutorial.fight),
      ),
      _ActionCard(
        icon: Icons.sports_martial_arts_rounded,
        title: 'Battle results',
        subtitle: [
          hasResults
              ? 'Watch yesterday\'s fights of your fighters and your challenger.'
              : 'Your first results arrive on day ${LoopStep.results}.',
          if (c.victoryStars > 0) 'Victory stars won: ${c.victoryStars} ★',
        ].join(' '),
        onTap: hasResults ? () => _openStep(ResultsScreen(controller: c), Tutorial.fight) : null,
      ),
      _ActionCard(
        icon: Icons.emoji_events_rounded,
        title: 'Week ranking',
        subtitle: switch (c.weeklyHero) {
          null => 'Once a week is over, its challengers are ranked by their stars. The first becomes a hero.',
          final hero => 'See how last week\'s challengers ranked. ${hero.card.subject} won with ${hero.stars} ★.',
        },
        onTap: c.weeklyHero == null ? null : () => _openStep(RankingScreen(controller: c), Tutorial.finale),
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
              IconButton(
                onPressed: () => _open(const HowToPlayScreen()),
                tooltip: 'How to play',
                icon: const Icon(Icons.help_outline_rounded),
              ),
              TicketChip(tickets: _controller.tickets),
              CancelServerButton(session: _controller),
              ContentEditorButton(session: _controller),
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
                          if (_controller.weeklyHero case final hero?) _WeeklyHeroCard(hero: hero),
                          _ActionCard(
                            icon: Icons.auto_awesome_rounded,
                            title: 'Summon',
                            subtitle:
                                '${_controller.tickets} pulls available · ${_controller.pool.length} characters in the pool',
                            onTap: () => _open(GachaScreen(controller: _controller), Tutorial.gacha),
                          ),
                          _ActionCard(
                            icon: Icons.collections_rounded,
                            title: 'Collection',
                            subtitle:
                                '${_controller.collection.length} characters'
                                '${_controller.upgradesAvailable > 0 ? ' · ${_controller.upgradesAvailable} upgrades ready' : ''}',
                            badge: _controller.upgradesAvailable,
                            onTap: () => _open(CollectionScreen(controller: _controller), Tutorial.upgrades),
                          ),
                          _ActionCard(
                            icon: Icons.shield_rounded,
                            title: 'Challengers',
                            subtitle: _controller.challengers.isEmpty
                                ? 'The challengers you draw, fight and boost, with their win rates.'
                                : '${_controller.challengers.length} encountered · see how they fare',
                            onTap: () => _open(ChallengersScreen(controller: _controller)),
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

/// The latest finale's winner, now in the gacha pool.
class _WeeklyHeroCard extends StatelessWidget {
  const _WeeklyHeroCard({required this.hero});

  final WeeklyHero hero;

  @override
  Widget build(BuildContext context) {
    final card = hero.card;
    return Card(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: SizedBox(width: 40, child: CardboardCard(child: SketchView(card.sketch))),
        title: Text('Weekly hero: ${card.subject} · "${card.title}"'),
        subtitle: Text(
          'Topped last week\'s ranking with ${hero.stars} ★ and joined the pool as a hero. '
          'Drawn by ${card.artist}.',
        ),
        trailing: const Icon(Icons.emoji_events_rounded, color: AppPalette.rarityHero),
      ),
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
