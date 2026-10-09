import 'dart:async';

import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/setup_plan.dart';
import '../widgets/cancel_server_button.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/phase_builder.dart';
import '../widgets/sign_out_button.dart';
import '../widgets/sketch_canvas.dart';
import 'drawing_screen.dart';

/// Initial drawing setup: every player draws characters of the others.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Who finished, whether the game launched or the server was cancelled.
    _refreshTimer = Timer.periodic(widget.controller.refreshInterval, (timer) async {
      if (widget.controller.phase != GamePhase.setup) return timer.cancel();
      try {
        await widget.controller.refreshServer();
      } catch (_) {
        // Polling: try again on the next tick.
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _draw(DrawingAssignment assignment) async {
    final controller = widget.controller;
    final previous = controller.setupDrawing(assignment);
    final reference = assignment.basedOn == null
        ? null
        : controller.assignments.where((a) => a.id == assignment.basedOn).map(controller.setupDrawing).first;
    final result = await Navigator.of(context).push<DrawingResult>(
      MaterialPageRoute(
        builder: (_) => DrawingScreen(
          subject: assignment.subject.name,
          prompt: assignment.prompt.label,
          hint: assignment.prompt.hint,
          rarity: assignment.prompt.rarity,
          initialTitle: previous?.title ?? '',
          reference: reference?.sketch,
        ),
      ),
    );
    if (result == null || !mounted) return;
    await runGameAction(context, () => controller.submitSetupDrawing(assignment, result.sketch, result.title));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final textTheme = Theme.of(context).textTheme;
    return PhaseBuilder(
      session: controller,
      phase: GamePhase.setup,
      builder: (context) {
        final done = controller.assignments.where((a) => controller.setupDrawing(a) != null).length;
        final server = controller.server;
        final friends = server.artists.where((p) => !p.isYou).toList();
        final friendsDone = friends.where((p) => server.setupDone.contains(p.id)).length;
        final waiting = controller.waitingForLaunch;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Initial drawings'),
            actions: [
              CancelServerButton(session: controller),
              SignOutButton(session: controller),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Draw your friends', style: textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        'These characters fill the gacha pool. Give each one a title. '
                        'You can redraw any of them until you finish.',
                      ),
                      const SizedBox(height: 12),
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: done / controller.assignments.length),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, value, _) => LinearProgressIndicator(value: value),
                      ),
                      const SizedBox(height: 4),
                      Text('$done of ${controller.assignments.length} done', style: textTheme.labelMedium),
                      const SizedBox(height: 12),
                      for (final assignment in controller.assignments) _tile(assignment),
                      const SizedBox(height: 12),
                      if (friends.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.groups_rounded),
                          title: Text('$friendsDone of ${friends.length} friends finished drawing'),
                          subtitle: TweenAnimationBuilder<double>(
                            tween: Tween(end: friendsDone / friends.length),
                            duration: const Duration(milliseconds: 500),
                            builder: (context, value, _) => LinearProgressIndicator(value: value),
                          ),
                        ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: controller.setupComplete && !waiting
                            ? () => runGameAction(context, controller.launch)
                            : null,
                        icon: const Icon(Icons.rocket_launch_rounded),
                        label: Text(waiting ? 'Waiting for your friends to finish…' : 'Finish and launch'),
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

  Widget _tile(DrawingAssignment assignment) {
    final controller = widget.controller;
    final drawing = controller.setupDrawing(assignment);
    final unlocked = controller.isUnlocked(assignment);
    final limit = assignment.prompt.rarity.drawTime;
    final limitLabel = limit == null
        ? 'no time limit'
        : limit.inMinutes > 0
        ? '${limit.inMinutes} min'
        : '${limit.inSeconds} s';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: SizedBox(
          width: 44,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: drawing == null
                ? Icon(unlocked ? Icons.draw_outlined : Icons.lock_outline_rounded, key: const ValueKey('empty'))
                : CardboardCard(key: ValueKey(drawing), child: SketchView(drawing.sketch)),
          ),
        ),
        title: Text('${assignment.subject.name} · ${assignment.prompt.label}'),
        subtitle: Text(
          drawing != null
              ? '"${drawing.title}"'
              : unlocked
              ? '${'★' * assignment.prompt.rarity.stars} · $limitLabel'
              : 'Draw the basic version first',
        ),
        trailing: drawing == null
            ? FilledButton.tonal(onPressed: unlocked ? () => _draw(assignment) : null, child: const Text('Draw'))
            : TextButton(
                onPressed: controller.waitingForLaunch ? null : () => _draw(assignment),
                child: const Text('Redraw'),
              ),
      ),
    );
  }
}
