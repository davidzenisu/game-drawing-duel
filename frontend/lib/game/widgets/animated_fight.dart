import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/daily_loop.dart';
import 'fight_stage.dart';
import 'stroke_effects.dart';

/// When in a beat the blow lands: the attacker winds up and strikes before,
/// the target reels after.
const _impactAt = 0.42;

/// Plays [beats] on a [FightStage]. The challenger drops in, the fighters
/// rise up and "Fight!" pops. In each beat the attacker winds up and
/// strikes, and the blow lands with a burst, a shake and a damage number;
/// hard hits shake the whole stage. Knocked out standees topple, and a
/// knockout ends on a slow final blow and a "K.O.!".
class AnimatedFight extends StatefulWidget {
  const AnimatedFight({
    super.key,
    required this.fight,
    required this.beats,
    this.beatDuration = const Duration(milliseconds: 560),
    this.entrance = true,
    this.loop = false,
    this.skip = false,
    this.onFinished,
  });

  final FightSetup fight;
  final List<FightBeat> beats;
  final Duration beatDuration;

  /// Brings the challenger and the fighters onto the stage first.
  final bool entrance;

  /// Starts the beats over after a short pause instead of finishing.
  final bool loop;

  /// Jumps straight to the end.
  final bool skip;
  final VoidCallback? onFinished;

  /// Blows from this much damage shake the stage.
  static const hardHit = 35;

  @override
  State<AnimatedFight> createState() => _AnimatedFightState();
}

class _AnimatedFightState extends State<AnimatedFight> with TickerProviderStateMixin {
  late final _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final _beat = AnimationController(vsync: this, duration: widget.beatDuration);
  late final _ticks = Listenable.merge([_entrance, _beat]);
  Timer? _timer;
  int _shown = 0;
  bool _done = false;

  FightBeat? get _current => _shown == 0 ? null : widget.beats[_shown - 1];

  /// The beat before the current one, whose HP stands until the blow lands.
  FightBeat? get _previous => _shown < 2 ? null : widget.beats[_shown - 2];

  bool get _landed => _current != null && _beat.value >= _impactAt;

  /// How far the target reels from the blow, 0 to 1.
  double get _reel => _landed ? const Interval(_impactAt, 1).transform(_beat.value) : 0;

  /// The last blow ends the fight rather than an exchange.
  bool get _knockout {
    final last = widget.beats.isEmpty ? null : widget.beats.last;
    return !widget.loop && last != null && (last.challengerHp == 0 || last.fighterHp.every((hp) => hp == 0));
  }

  bool get _finalBlow => _knockout && _shown == widget.beats.length;

  @override
  void initState() {
    super.initState();
    if (widget.skip) {
      _finish(inBuild: true);
    } else if (widget.entrance) {
      _entrance.forward().whenCompleteOrCancel(_next);
    } else {
      _entrance.value = 1;
      _timer = Timer(widget.beatDuration * 0.5, _next);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: straight to the outcome.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _finish(inBuild: true);
  }

  @override
  void didUpdateWidget(AnimatedFight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.skip && !oldWidget.skip) _finish(inBuild: true);
  }

  void _next() {
    if (!mounted || _done) return;
    final beats = widget.beats;
    if (_shown >= beats.length) {
      if (!widget.loop) return _finish();
      // Pause for a moment, then start the exchange again.
      _timer = Timer(widget.beatDuration * 2, () {
        if (!mounted || _done) return;
        setState(() => _shown = 0);
        _next();
      });
      return;
    }
    setState(() => _shown++);
    // The blow that ends the fight plays in slow motion.
    _beat.duration = _finalBlow ? widget.beatDuration * 1.8 : widget.beatDuration;
    _beat.forward(from: 0).whenCompleteOrCancel(_next);
  }

  /// Shows the end; [inBuild] when a build follows anyway.
  void _finish({bool inBuild = false}) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    _entrance.value = 1;
    _beat.value = 1;
    _shown = widget.beats.length;
    if (!inBuild) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _done = true;
    _timer?.cancel();
    _entrance.dispose();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fight = widget.fight;
    // The stage only rebuilds once a beat; the standees animate inside it.
    final stage = RepaintBoundary(
      child: FightStage(
        theme: fight.challenger.scenery,
        challenger: fight.challenger,
        fighters: fight.fighters,
        wrapChallenger: (context, standee) => _animated(FightBeat.challenger, standee),
        wrapFighter: (context, index, standee) => _animated(index, standee),
        wrapNameplate: (context, index, plate) => AnimatedBuilder(
          animation: _entrance,
          child: plate,
          builder: (context, plate) => _enteringNameplate(index, plate!),
        ),
      ),
    );
    return ClipRect(
      child: AnimatedBuilder(
        animation: _ticks,
        child: stage,
        builder: (context, stage) {
          final beat = _current;
          final reel = _reel;
          final hard = _landed && (beat!.damage >= AnimatedFight.hardHit || _finalBlow);
          final quake = hard ? pow(1 - reel, 2).toDouble() : 0.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Scaled up a touch while it shakes, so no edge shows.
              Transform.scale(
                scale: 1 + 0.03 * quake,
                child: Transform.translate(
                  offset: Offset(sin(reel * pi * 10) * 7 * quake, cos(reel * pi * 8) * 4 * quake),
                  child: stage,
                ),
              ),
              if (widget.entrance) _fightCall(),
              if (_finalBlow && _landed) _knockoutCall(),
            ],
          );
        },
      ),
    );
  }

  /// The challenger's nameplate slides in from the side, the fighters'
  /// come up with them.
  Widget _enteringNameplate(int index, Widget plate) {
    final isChallenger = index == FightBeat.challenger;
    final enterAt = isChallenger ? 0.2 : _enterAt(index);
    final slide = Interval(enterAt, enterAt + 0.35, curve: Curves.easeOutCubic).transform(_entrance.value);
    return Opacity(
      opacity: slide,
      child: Transform.translate(
        offset: isChallenger ? Offset((1 - slide) * 80, 0) : Offset(0, (1 - slide) * 40),
        child: plate,
      ),
    );
  }

  static double _enterAt(int index) => index == FightBeat.challenger ? 0 : 0.25 + index * 0.08;

  Widget _fightCall() {
    final e = _entrance.value;
    final opacity = min(const Interval(0.6, 0.68).transform(e), 1 - const Interval(0.9, 1).transform(e));
    if (opacity <= 0) return const SizedBox.shrink();
    final pop = const Interval(0.6, 0.78, curve: Curves.easeOutBack).transform(e);
    return _Call(text: 'Fight!', color: Colors.white, scale: 0.4 + 0.6 * pop, opacity: opacity);
  }

  Widget _knockoutCall() {
    final pop = const Interval(0, 0.35, curve: Curves.easeOutBack).transform(_reel);
    return _Call(
      text: 'K.O.!',
      color: AppPalette.rarityLegend,
      scale: 0.3 + 0.7 * pop,
      opacity: const Interval(0, 0.15).transform(_reel),
    );
  }

  int _hpOf(FightBeat? beat, int index) => beat == null
      ? FightScript.maxHp
      : index == FightBeat.challenger
      ? beat.challengerHp
      : beat.fighterHp[index];

  Color _burstColor(FightBeat beat) {
    if (beat.attacker == FightBeat.challenger) return AppPalette.hurry;
    // The fighters' element, if one of them has one.
    for (final (i, fighter) in widget.fight.fighters.indexed) {
      final element = fighter.element;
      if (element != null && _hpOf(_previous, i) > 0) return elementColor(element);
    }
    return AppPalette.rarityLegend;
  }

  Widget _animated(int index, Widget standee) => AnimatedBuilder(
    animation: _ticks,
    // Effects keep animating inside without repainting the rest.
    child: RepaintBoundary(child: standee),
    builder: (context, standee) => _standee(index, standee!),
  );

  Widget _standee(int index, Widget standee) {
    final beat = _current;
    final isChallenger = index == FightBeat.challenger;
    final landed = _landed;
    final reel = _reel;
    final hp = _hpOf(landed ? beat : _previous, index);
    final attacking =
        beat != null &&
        (beat.attacker == index || (beat.attacker == FightBeat.team && !isChallenger && _hpOf(_previous, index) > 0));
    final hit = landed && beat!.target == index;
    final hard = hit && (beat.damage >= AnimatedFight.hardHit || _finalBlow);

    // The challenger drops in from above, the fighters rise one by one.
    final e = _entrance.value;
    final enterAt = _enterAt(index);
    final enter = Interval(enterAt, enterAt + (isChallenger ? 0.45 : 0.3), curve: Curves.easeOutBack).transform(e);
    final entering = Offset(0, (1 - enter) * (isChallenger ? -240 : 160));
    final visible = Interval(enterAt, enterAt + 0.12).transform(e);

    // Fighters attacking together strike a moment apart.
    final stagger = attacking && beat.attacker == FightBeat.team ? index * 0.03 : 0.0;
    final lunge = attacking ? _lunge((_beat.value - stagger).clamp(0.0, 1.0)) * (isChallenger ? 40 : -40) : 0.0;
    final shake = hit ? sin(reel * pi * 8) * (hard ? 14 : 9) * (1 - reel) : 0.0;
    final flash = hit ? 1 - reel : 0.0;

    return Opacity(
      opacity: visible,
      child: Transform.translate(
        offset: entering,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: hp / FightScript.maxHp),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
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
                  _Topple(
                    knockedOut: hp == 0,
                    // The challenger falls back, fighters to alternating sides.
                    direction: isChallenger || index.isEven ? -1 : 1,
                    child: Transform.translate(
                      offset: Offset(shake, lunge),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(Colors.white.withValues(alpha: flash * 0.6), BlendMode.srcATop),
                        child: standee,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hit)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BurstPainter(progress: reel, color: _burstColor(beat), hard: hard),
                  ),
                ),
              ),
            // Pops up over the card, so it never leaves the stage.
            if (hit && beat.damage > 0)
              Positioned.fill(
                child: Align(
                  alignment: Alignment(0, -0.3 - reel * 0.5),
                  child: Opacity(
                    opacity: 1 - const Interval(0.6, 1).transform(reel),
                    child: Transform.scale(
                      scale: 1 + (hard ? 0.8 : 0.4) * pow(1 - reel, 3),
                      child: Text(
                        '-${beat.damage}',
                        style: TextStyle(
                          fontSize: hard ? 34 : 26,
                          fontWeight: FontWeight.w900,
                          color: hard ? AppPalette.rarityLegend : AppPalette.hurry,
                          shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// How far along its lunge an attacker is at [t] of a beat: it winds up
/// back a bit, strikes until the blow lands and settles back.
double _lunge(double t) {
  if (t < 0.25) return -0.2 * Curves.easeOut.transform(t / 0.25);
  if (t < _impactAt) return -0.2 + 1.2 * Curves.easeIn.transform((t - 0.25) / (_impactAt - 0.25));
  return 1 - Curves.easeOut.transform((t - _impactAt) / (1 - _impactAt));
}

/// Tips a knocked out standee over on its base and greys it out.
class _Topple extends StatelessWidget {
  const _Topple({required this.knockedOut, required this.direction, required this.child});

  final bool knockedOut;
  final int direction;
  final Widget child;

  static const _grey = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];
  static const _identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: knockedOut ? 1 : 0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.bounceOut,
      child: child,
      builder: (context, fall, child) => Opacity(
        opacity: 1 - 0.5 * fall.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: direction * 0.35 * fall,
          alignment: Alignment.bottomCenter,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix([
              for (var i = 0; i < 20; i++) _identity[i] + (_grey[i] - _identity[i]) * fall.clamp(0.0, 1.0),
            ]),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Rays and a ring bursting out where a blow lands.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color, required this.hard});

  final double progress;
  final Color color;
  final bool hard;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    final center = Offset(size.width / 2, size.height * 0.42);
    final radius = size.width * (hard ? 0.75 : 0.55);
    final fade = 1 - progress;
    final paint = Paint()
      ..color = color.withValues(alpha: fade)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (hard ? 7 : 5) * fade;
    final rays = hard ? 12 : 8;
    for (var i = 0; i < rays; i++) {
      final direction = Offset.fromDirection(i * 2 * pi / rays + 0.3);
      final inner = radius * (0.25 + 0.55 * progress);
      final outer = radius * (0.45 + 0.75 * progress);
      canvas.drawLine(center + direction * inner, center + direction * outer, paint);
    }
    canvas.drawCircle(
      center,
      radius * (0.2 + 0.8 * progress),
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * fade,
    );
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.hard != hard;
}

/// A big word across the stage, like "Fight!".
class _Call extends StatelessWidget {
  const _Call({required this.text, required this.color, required this.scale, required this.opacity});

  final String text;
  final Color color;
  final double scale;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: color,
                shadows: const [
                  Shadow(offset: Offset(3, 3), color: AppPalette.nameplateBottom),
                  Shadow(blurRadius: 12, color: Colors.black54),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
