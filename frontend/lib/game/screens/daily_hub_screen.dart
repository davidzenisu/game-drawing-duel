import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../rules/themes.dart';
import '../tutorials.dart';
import '../unavailable.dart';
import '../widgets/admin_menu.dart';
import '../widgets/game_action.dart';
import '../widgets/notification_board.dart';
import '../widgets/countdown.dart';
import '../widgets/account_menu.dart';
import '../widgets/themed_background.dart';
import '../widgets/tutorial_dialog.dart';
import '../widgets/ticket_chip.dart';
import '../widgets/hurry_button.dart';
import '../widgets/hub_tile.dart';
import 'boost_screen.dart';
import 'drawing_recap_screen.dart';
import 'drawing_screen.dart';
import 'fight_setup_screen.dart';
import 'heroes_menu_screen.dart';
import 'how_to_play_screen.dart';
import 'prompt_screen.dart';
import 'speed_finale_screen.dart';

/// The daily routine: draw a challenger, pull, fight and upgrade.
class DailyHubScreen extends StatefulWidget {
  const DailyHubScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<DailyHubScreen> createState() => _DailyHubScreenState();
}

class _DailyHubScreenState extends State<DailyHubScreen> {
  GameSession get _controller => widget.controller;
  Timer? _speedTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
    // In speed mode, a day ends early once everyone is done: keep up.
    if (_controller.server.isSpeed) {
      _speedTimer = Timer.periodic(_controller.refreshInterval, (_) => _refreshQuietly());
    }
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshQuietly() async {
    if (_controller.sessionOver) return _speedTimer?.cancel();
    try {
      await _controller.refreshDay();
    } catch (_) {
      // Polling: try again on the next tick.
    }
    // The session just ended: on to the final ranking.
    if (_controller.sessionOver && mounted) _openFinale();
  }

  void _openFinale() => _open(SpeedFinaleScreen(controller: _controller));

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
          noBackingOut: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (!await runGameAction(context, () => _controller.submitChallenger(result.sketch)) || !mounted) return;
    await _open(DrawingRecapScreen(subject: prompt.subject.name, result: result, theme: prompt.theme));
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
    if (_controller.sessionOver && mounted) _openFinale();
  }

  /// Speed mode and test sessions: you're done for today; the day moves on
  /// once everyone is.
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
    if (_controller.sessionOver && mounted) _openFinale();
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

  /// The four steps of the loop, two by two: greyed out on days without
  /// anything to do for them, e.g. all but the prompt on day 1, or the
  /// prompt and drawing in speed mode's last days.
  List<Widget> _steps() {
    final c = _controller;
    final over = c.sessionOver;
    final toDraw = c.promptToDraw;
    final fight = c.yourFight;
    return [
      HubTile(
        icon: Icons.edit_note_rounded,
        title: 'Choose a challenger',
        done: c.yourPrompt != null,
        unavailable: Unavailable.prompt(c),
        onTap: !over && c.promptsToday && c.yourPrompt == null
            ? () => _openStep(PromptScreen(controller: c), Tutorial.prompt)
            : null,
      ),
      HubTile(
        icon: Icons.brush_rounded,
        title: 'Draw a challenger',
        done: c.challengerDrawn,
        unavailable: Unavailable.draw(c),
        onTap: !over && toDraw != null && !c.challengerDrawn ? _drawChallenger : null,
      ),
      HubTile(
        icon: Icons.keyboard_double_arrow_up_rounded,
        title: 'Boost challengers',
        done: c.boostTargets.isNotEmpty && !c.canBoost,
        unavailable: Unavailable.boost(c),
        badge: c.canBoost ? c.boostStarsLeft : 0,
        // Boosts can be moved all day, even once all stars are given.
        onTap: !over && c.boostTargets.isNotEmpty ? () => _openStep(BoostScreen(controller: c), Tutorial.boost) : null,
      ),
      HubTile(
        icon: Icons.groups_rounded,
        title: 'Pick your fighters',
        done: fight != null,
        unavailable: Unavailable.fight(c),
        onTap: !over && c.fightChallenger != null && (fight != null || c.availableFighters.isNotEmpty)
            ? () => _openStep(FightSetupScreen(controller: c), Tutorial.fight)
            : null,
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
            // The day and its theme show in the body, where a phone has
            // room for them next to all the actions.
            automaticallyImplyLeading: false,
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
              NotificationBoardButton(session: _controller),
              TicketChip(tickets: _controller.tickets),
              AdminMenu(session: _controller),
              AccountMenu(session: _controller, canCancelServer: true),
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
                          // The day's free hurry, above the drawing step.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: _DayHeader(day: _controller.day, theme: theme, color: onScenery),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: HurryButton(controller: _controller)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_controller.dayEndsAt case final endsAt?)
                            Center(
                              child: Countdown(
                                endsAt: endsAt,
                                label: 'Day ${_controller.day} of ${SpeedMode.days.length}',
                                onDone: _refreshQuietly,
                              ),
                            ),
                          if (_controller.sessionOver)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.flag_rounded),
                                title: const Text('The speed session is over'),
                                subtitle: const Text('Every challenger had its fight. See how they ranked!'),
                                trailing: const Icon(Icons.emoji_events_rounded, color: AppPalette.rarityLegend),
                                onTap: _openFinale,
                              ),
                            ),
                          if (_controller.canEndDay) _dayEndedCard(),
                          const SizedBox(height: 8),
                          HubGrid(tiles: _steps()),
                          const SizedBox(height: 4),
                          HubTile(
                            icon: Icons.military_tech_rounded,
                            title: 'Heroes',
                            height: 112,
                            badge: _controller.upgradesAvailable,
                            onTap: () => _open(HeroesMenuScreen(controller: _controller)),
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

/// Today's day number and theme, big over the scenery.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.theme, required this.color});

  final int day;
  final DailyTheme theme;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const shadow = [Shadow(color: Colors.black26, blurRadius: 4)];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
      child: Column(
        key: ValueKey(day),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Day $day',
            style: textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.w900, shadows: shadow),
          ),
          Text(
            theme.label,
            style: textTheme.titleMedium?.copyWith(color: color, shadows: shadow),
          ),
        ],
      ),
    );
  }
}
