import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../logic/daily_loop.dart';
import '../logic/game_controller.dart';
import '../widgets/card_art.dart';
import '../widgets/sketch_canvas.dart';
import '../widgets/animated_fight.dart';

/// Fights you were part of: the fighters you picked yesterday and the
/// challenger you drew two days ago.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final yourFights = controller.yourFightResults;
    final yourChallenger = controller.yourChallengerResults;
    return Scaffold(
      appBar: AppBar(title: const Text('Battle results')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(title: 'Your fighters', empty: 'You did not pick fighters yesterday.', fights: yourFights),
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Your challenger',
                    empty: 'Nobody fought a challenger of yours today.',
                    fights: yourChallenger,
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.empty, required this.fights});

  final String title;
  final String empty;
  final List<FightSetup> fights;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (fights.isEmpty) Text(empty),
        for (final fight in fights)
          Card(
            child: ListTile(
              leading: SizedBox(width: 40, child: CardboardCard(child: SketchView(fight.challenger.sketch))),
              title: Text('${fight.challenger.subject} · ${fight.challenger.title}'),
              subtitle: Text(
                "${fight.owner.isYou ? 'Your' : "${fight.owner.name}'s"} ${fight.fighters.length} fighter${fight.fighters.length == 1 ? '' : 's'} · "
                '${fight.votes.length} votes',
              ),
              trailing: const Icon(Icons.play_circle_fill_rounded, size: 32),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FightReplayScreen(fight: fight))),
            ),
          ),
      ],
    );
  }
}

/// Plays out a fight that ends with the outcome the votes decided.
class FightReplayScreen extends StatefulWidget {
  const FightReplayScreen({super.key, required this.fight});

  final FightSetup fight;

  @override
  State<FightReplayScreen> createState() => _FightReplayScreenState();
}

class _FightReplayScreenState extends State<FightReplayScreen> {
  late final List<FightBeat> _beats = FightScript.build(
    fighterCount: widget.fight.fighters.length,
    fightersWin: widget.fight.fightersWin,
    random: Random(widget.fight.id.hashCode),
  );
  bool _skip = false;
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('The fight'),
        actions: [if (!_finished) TextButton(onPressed: () => setState(() => _skip = true), child: const Text('Skip'))],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedFight(
              fight: widget.fight,
              beats: _beats,
              skip: _skip,
              onFinished: () => setState(() => _finished = true),
            ),
          ),
          if (_finished) _outcome(context),
        ],
      ),
    );
  }

  Widget _outcome(BuildContext context) {
    final fight = widget.fight;
    final fightersWin = fight.fightersWin;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.4),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (context, value, child) => Transform.scale(scale: value, child: child),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events_rounded, size: 56, color: AppPalette.rarityLegend),
                    Text(
                      fightersWin ? 'The fighters win!' : '${fight.challenger.subject} wins!',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text('Votes: ${fight.fighterVotes} for the fighters · ${fight.challengerVotes} for the challenger'),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
