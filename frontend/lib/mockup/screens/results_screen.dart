import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../logic/daily_loop.dart';
import '../logic/game_controller.dart';
import '../widgets/card_art.dart';
import '../widgets/sketch_canvas.dart';
import '../widgets/fight_stage.dart';

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

class _FightReplayScreenState extends State<FightReplayScreen> with TickerProviderStateMixin {
  late final List<FightBeat> _beats = FightScript.build(
    fighterCount: widget.fight.fighters.length,
    fightersWin: widget.fight.fightersWin,
    random: Random(widget.fight.id.hashCode),
  );
  late final _lunge = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final _impact = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  Timer? _timer;
  int _shown = 0;

  bool get _finished => _shown >= _beats.length;

  FightBeat? get _beat => _shown == 0 ? null : _beats[_shown - 1];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 750), (_) => _next());
  }

  void _next() {
    if (_finished) {
      _timer?.cancel();
      return;
    }
    setState(() => _shown++);
    _lunge.forward(from: 0).then((_) {
      if (mounted) _lunge.reverse();
    });
    _impact.forward(from: 0);
  }

  void _skip() {
    _timer?.cancel();
    setState(() => _shown = _beats.length);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lunge.dispose();
    _impact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fight = widget.fight;
    return Scaffold(
      appBar: AppBar(
        title: const Text('The fight'),
        actions: [if (!_finished) TextButton(onPressed: _skip, child: const Text('Skip'))],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_lunge, _impact]),
              builder: (context, _) => FightStage(
                theme: fight.challenger.scenery,
                challenger: fight.challenger,
                fighters: fight.fighters,
                wrapChallenger: (context, standee) => _wrap(-1, standee),
                wrapFighter: (context, index, standee) => _wrap(index, standee),
              ),
            ),
          ),
          if (_finished) _outcome(context),
        ],
      ),
    );
  }

  Widget _wrap(int index, Widget standee) {
    final beat = _beat;
    final hp = beat == null
        ? FightScript.maxHp
        : index == -1
        ? beat.challengerHp
        : beat.fighterHp[index];
    final attacking = beat != null && beat.attacker == index;
    final hit = beat != null && beat.target == index;
    // The challenger lunges down at the fighters, fighters lunge up.
    final lunge = attacking ? Curves.easeOut.transform(_lunge.value) * (index == -1 ? 36 : -36) : 0.0;
    final shake = hit ? sin(_impact.value * pi * 8) * 8 * (1 - _impact.value) : 0.0;
    final knockedOut = hp == 0;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: hp / FightScript.maxHp),
                duration: const Duration(milliseconds: 400),
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 7,
                    color: Color.lerp(AppPalette.hpLow, AppPalette.hpHigh, value),
                    backgroundColor: Colors.black26,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedOpacity(
                opacity: knockedOut ? 0.45 : 1,
                duration: const Duration(milliseconds: 400),
                child: AnimatedRotation(
                  turns: knockedOut ? -0.04 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Transform.translate(offset: Offset(shake, lunge), child: standee),
                ),
              ),
            ],
          ),
        ),
        if (hit && beat.damage > 0)
          Positioned(
            top: 10 - _impact.value * 40,
            child: Opacity(
              opacity: 1 - _impact.value,
              child: Text(
                '-${beat.damage}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.hurry,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
          ),
      ],
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
