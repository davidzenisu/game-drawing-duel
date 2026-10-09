import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../logic/daily_loop.dart';
import 'fight_stage.dart';

/// Plays [beats] on a [FightStage]: attackers lunge, targets shake, HP bars
/// drain and damage numbers pop up.
class AnimatedFight extends StatefulWidget {
  const AnimatedFight({
    super.key,
    required this.fight,
    required this.beats,
    this.beatDuration = const Duration(milliseconds: 420),
    this.loop = false,
    this.skip = false,
    this.onFinished,
  });

  final FightSetup fight;
  final List<FightBeat> beats;
  final Duration beatDuration;

  /// Starts over after a short pause instead of finishing.
  final bool loop;

  /// Jumps straight to the end.
  final bool skip;
  final VoidCallback? onFinished;

  @override
  State<AnimatedFight> createState() => _AnimatedFightState();
}

class _AnimatedFightState extends State<AnimatedFight> with TickerProviderStateMixin {
  late final _lunge = AnimationController(vsync: this, duration: widget.beatDuration * 0.45);
  late final _impact = AnimationController(vsync: this, duration: widget.beatDuration * 0.8);
  Timer? _timer;
  int _shown = 0;

  FightBeat? get _beat => _shown == 0 ? null : widget.beats[_shown - 1];

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.beatDuration, (_) => _next());
  }

  @override
  void didUpdateWidget(AnimatedFight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.skip && !oldWidget.skip) _finish();
  }

  void _next() {
    if (_shown >= widget.beats.length) {
      if (widget.loop) {
        // Pause for a beat, then start the exchange again.
        _timer?.cancel();
        _timer = Timer(widget.beatDuration * 2, () {
          if (!mounted) return;
          setState(() => _shown = 0);
          _start();
        });
      } else {
        _finish();
      }
      return;
    }
    setState(() => _shown++);
    _lunge.forward(from: 0).then((_) {
      if (mounted) _lunge.reverse();
    });
    _impact.forward(from: 0);
  }

  void _finish() {
    _timer?.cancel();
    setState(() => _shown = widget.beats.length);
    widget.onFinished?.call();
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
    return AnimatedBuilder(
      animation: Listenable.merge([_lunge, _impact]),
      builder: (context, _) => FightStage(
        theme: fight.challenger.scenery,
        challenger: fight.challenger,
        fighters: fight.fighters,
        wrapChallenger: (context, standee) => _wrap(FightBeat.challenger, standee),
        wrapFighter: (context, index, standee) => _wrap(index, standee),
      ),
    );
  }

  Widget _wrap(int index, Widget standee) {
    final beat = _beat;
    final isChallenger = index == FightBeat.challenger;
    final hp = beat == null
        ? FightScript.maxHp
        : isChallenger
        ? beat.challengerHp
        : beat.fighterHp[index];
    final previousHp = _shown < 2
        ? FightScript.maxHp
        : isChallenger
        ? widget.beats[_shown - 2].challengerHp
        : widget.beats[_shown - 2].fighterHp[index];
    final attacking =
        beat != null &&
        (beat.attacker == index || (beat.attacker == FightBeat.team && !isChallenger && previousHp > 0));
    final hit = beat != null && beat.target == index;
    // The challenger lunges down at the fighters, fighters lunge up.
    final lunge = attacking ? Curves.easeOut.transform(_lunge.value) * (isChallenger ? 40 : -40) : 0.0;
    final shake = hit ? sin(_impact.value * pi * 8) * 9 * (1 - _impact.value) : 0.0;
    final flash = hit ? (1 - _impact.value) : 0.0;
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
                duration: const Duration(milliseconds: 250),
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
                duration: const Duration(milliseconds: 300),
                child: AnimatedRotation(
                  turns: knockedOut ? -0.04 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Transform.translate(
                    offset: Offset(shake, lunge),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(Colors.white.withValues(alpha: flash * 0.6), BlendMode.srcATop),
                      child: standee,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hit && beat.damage > 0)
          Positioned(
            top: 10 - _impact.value * 36,
            child: Opacity(
              opacity: 1 - _impact.value,
              child: Text(
                '-${beat.damage}',
                style: const TextStyle(
                  fontSize: 28,
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
}
