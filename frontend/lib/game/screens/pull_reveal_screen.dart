import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/buzz.dart';
import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/gacha.dart';
import '../rules/models.dart';
import '../rules/upgrades.dart';
import '../sound.dart';
import '../widgets/card_art.dart';
import '../widgets/gacha_box.dart';
import '../widgets/key_controls.dart';

/// How long a card on its own builds up before it flips: the rarer, the
/// longer.
Duration _buildUpFor(Rarity rarity) => Duration(milliseconds: 800 + 400 * rarity.index);

/// How long a cut open box shakes before it opens: the rarer, the longer.
Duration _boxBuildUpFor(Rarity rarity) => Duration(milliseconds: 500 + 350 * rarity.index);

/// How long a pull takes to come out of its box, from the flaps opening
/// to the box sinking away.
const _pullOutTime = Duration(milliseconds: 1300);

/// How long the phone buzzes as a box opens: the rarer the best pull
/// inside, the longer and so the heavier.
@visibleForTesting
Duration openingBuzzFor(Rarity rarity) => Duration(milliseconds: const [150, 300, 500, 800][rarity.index]);

/// How long a box takes to drop in and land, before its tape can be cut.
const _landTime = Duration(milliseconds: 650);

/// How far above its place a landing box is at [t] of its landing: it drops
/// in and lands with two small bounces.
double _dropAt(double t) => -560 * (1 - Curves.bounceOut.transform(t));

/// Plays the landing thud as a landing box first touches down
/// ([Curves.bounceOut]'s first bounce), not when skipped straight down.
void _thudOnLanding(AnimationController land) {
  var heard = false;
  land.addListener(() {
    if (heard || land.value < 1 / 2.75) return;
    heard = true;
    if (land.isAnimating) sound.boxLands();
  });
}

/// The light peeking out of a cut [cut] that far: white, turning to the
/// [rarest] pull's colour only towards the end.
Color _peek(double cut, Color rarest) =>
    Color.lerp(Colors.white, rarest, Curves.easeIn.transform(const Interval(0.75, 1).transform(cut)))!;

/// What to do while the tape is still whole.
const _cutHint = 'Swipe along the tape to cut it open';

/// The build-up's colour at [t]: it climbs through the rarities' colours up
/// to [rarity]'s, so the rarer the pull, the further it climbs.
Color _climb(double t, Rarity rarity) {
  final steps = rarity.index;
  if (steps == 0) return Color.lerp(Colors.white, rarity.color, t)!;
  final position = t * steps;
  final step = min(position.floor(), steps - 1);
  return Color.lerp(
    Rarity.values[step].color,
    Rarity.values[step + 1].color,
    Curves.easeIn.transform((position - step).clamp(0.0, 1.0)),
  )!;
}

/// The box a [banner]'s pulls come out of: the weekly rate-up's is taped in
/// the legends' gold.
GachaBox _box(
  GachaBanner banner, {
  required BoxCamera camera,
  required GachaBoxLayer layer,
  required double cut,
  required double open,
  required double leak,
  required Color glow,
}) => GachaBox(
  camera: camera,
  layer: layer,
  cut: cut,
  open: open,
  leak: leak,
  glow: glow,
  tape: banner == GachaBanner.weekly ? Rarity.legend.color : GachaBox.plainTape,
  label: banner == GachaBanner.weekly ? 'WEEKLY HERO' : 'DRAWING DUEL',
);

/// Cutting a box's tape open by swiping along it, left to right: the phone
/// buzzes as the cut starts and runs, the tape tears as loud as the finger
/// is fast, and once it's through, it snaps free and [onCut].
class _TapeCut {
  _TapeCut(this.onCut);

  final VoidCallback onCut;
  double progress = 0;

  /// The tearing, while the finger is on the tape.
  SoundLoop? _tearing;

  /// Whether a finger is on the tape.
  bool cutting = false;

  bool get done => progress >= 1;

  /// How far a cut goes before it's through: the last bit cuts itself, so
  /// a swipe that falls a little short still opens the box.
  static const through = 0.9;

  /// Cuts [dx] further along a tape [length] long on screen.
  void drag(double dx, double length) {
    if (done || dx <= 0) return;
    final before = progress;
    progress = min(1, progress + dx / length);
    if (progress >= through) progress = 1;
    if (before == 0) {
      HapticFeedback.heavyImpact();
    } else if ((progress * 8).floor() > (before * 8).floor()) {
      HapticFeedback.vibrate();
    }
    // A full swipe across in about half a second tears at full volume.
    (_tearing ??= sound.tapeTearing())?.volume = (dx / length / 0.03).clamp(0.3, 1.0);
    if (done) {
      cutting = false;
      _silence();
      sound.tapeCut();
      onCut();
    }
  }

  /// The finger left the tape.
  void release() {
    cutting = false;
    _tearing?.volume = 0;
  }

  void _silence() {
    _tearing?.stop();
    _tearing = null;
  }

  /// Skips the cutting.
  void skip() {
    progress = 1;
    _silence();
  }

  /// Cutting on its own, from the keyboard.
  AnimationController? _auto;

  /// Cuts the tape all the way through on its own, like a full swipe across
  /// a tape [length] long (from the keyboard), calling [changed] as it goes.
  void cutThrough(TickerProvider vsync, {required double Function() length, required VoidCallback changed}) {
    if (done || _auto != null) return;
    cutting = true;
    _auto = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 450), value: progress)
      ..addListener(() {
        final tape = length();
        drag((_auto!.value - progress) * tape, tape);
        changed();
      })
      ..forward();
  }

  void dispose() {
    _auto?.dispose();
    _silence();
  }
}

/// The scissors on the tape: sliding along it to show what to do until the
/// cut starts, then at the cut, fading out as it gets going.
Widget _scissors(BoxCamera camera, _TapeCut cut, double hint) {
  final at = cut.progress > 0 ? cut.progress : Curves.easeInOut.transform(hint);
  return IgnorePointer(
    child: Transform.translate(
      offset: GachaBox.cutAt(camera, at) + const Offset(0, -18),
      child: Opacity(
        opacity: cut.progress > 0
            ? 1 - const Interval(0, 0.25).transform(cut.progress)
            : cut.cutting
            ? 1
            : 0.85 * sin(hint * pi),
        child: Icon(
          Icons.content_cut_rounded,
          size: 34,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
        ),
      ),
    ),
  );
}

/// How far a cut box shakes at [charge] of its build-up: harder the rarer
/// the best card inside.
double _boxShake(double charge, Rarity rarity) => sin(charge * pi * 18) * charge * (1 + rarity.index * 2.5);

/// [camera] pushing in on a box as its build-up runs, [charge] from 0 to 1.
BoxCamera _pushedIn(BoxCamera camera, double charge) =>
    BoxCamera.lerp(camera, camera.copyWith(yaw: -0.3, zoom: camera.zoom * 1.12), Curves.easeInOut.transform(charge));

/// The camera on a box, swaying gently round it as [sway] runs from 0 to
/// 1, and shaking by [shake].
BoxCamera _swaying(double sway, {double zoom = 1, Offset shift = Offset.zero, double shake = 0}) {
  final t = sway * 2 * pi;
  return BoxCamera(
    yaw: -0.5 + 0.12 * sin(t),
    pitch: 0.6 + 0.05 * sin(2 * t),
    roll: shake * 0.004,
    zoom: zoom,
    shift: shift + Offset(shake, 0),
  );
}

/// Full screen reveal of pulls, out of a cardboard box in 3D. The player
/// cuts its tape open with a swipe, the light of the rarest pull inside
/// peeking out of the cut. A single pull's box then shakes, opens, and the
/// card rises out of it, flips and bursts. A multi-pull's cards fan out of
/// the box into a carousel face down, every back glowing in its rarity's
/// colour, then reveal one by one, and it ends on an overview of them all.
class PullRevealScreen extends StatefulWidget {
  const PullRevealScreen({
    super.key,
    required this.outcomes,
    this.owned = const {},
    this.banner = GachaBanner.standard,
  });

  final List<PullOutcome> outcomes;

  /// The banner pulled on, for its box.
  final GachaBanner banner;

  /// Your characters after the pulls, by card id: a duplicate tells
  /// whether its next upgrade is ready. Characters show plain here, so the
  /// drawing stays the focus.
  final Map<String, OwnedCard> owned;

  @override
  State<PullRevealScreen> createState() => _PullRevealScreenState();
}

class _PullRevealScreenState extends State<PullRevealScreen> {
  PullOutcome? _spotlight;

  /// The keys reach whichever is in front: the card in the spotlight, or
  /// the multi-pull's box, carousel and overview.
  final _multi = GlobalKey<_MultiPullState>();
  var _spotlightKey = GlobalKey<_SingleRevealState>();

  // The music steps back for the summon's own sounds.
  @override
  void initState() {
    super.initState();
    sound.duck();
  }

  @override
  void dispose() {
    sound.unduck();
    super.dispose();
  }

  /// While a multi-pull reveals its cards one by one: how far it got, and
  /// what comes after this card or after skipping the rest.
  String? _progress;
  VoidCallback? _next;
  VoidCallback? _skip;

  bool get _single => widget.outcomes.length == 1;

  void _reveal(PullOutcome outcome, String progress, VoidCallback next, VoidCallback skip) => setState(() {
    _spotlight = outcome;
    _spotlightKey = GlobalKey();
    _progress = progress;
    _next = next;
    _skip = skip;
  });

  /// Shows a card again from the overview.
  void _inspect(PullOutcome outcome) => setState(() {
    _spotlight = outcome;
    _spotlightKey = GlobalKey();
    _progress = _next = _skip = null;
  });

  /// Hides the spotlight, then calls [then].
  void _leave(VoidCallback? then) {
    setState(() {
      _spotlight = null;
      _progress = _next = _skip = null;
    });
    then?.call();
  }

  void _close() => Navigator.of(context).pop();

  /// → , Enter or Space: what a swipe or tap does next.
  void _advance() {
    final spotlight = _spotlightKey.currentState;
    spotlight != null ? spotlight.advance() : _multi.currentState?.advance();
  }

  @override
  Widget build(BuildContext context) {
    final spotlight = _single ? widget.outcomes.single : _spotlight;
    return KeyControls(
      onRight: _advance,
      onConfirm: _advance,
      onBack: _close,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              if (!_single)
                Positioned.fill(
                  child: _MultiPull(
                    key: _multi,
                    outcomes: widget.outcomes,
                    banner: widget.banner,
                    owned: widget.owned,
                    onReveal: _reveal,
                    onInspect: _inspect,
                    onDone: _close,
                  ),
                ),
              if (spotlight != null)
                Positioned.fill(
                  child: _SingleReveal(
                    key: _spotlightKey,
                    outcome: spotlight,
                    banner: widget.banner,
                    owned: widget.owned[spotlight.card.id],
                    // A single pull comes out of its own box; a multi-pull's
                    // cards came out of theirs already.
                    boxed: _single,
                    // Cards shown again from the overview are face up already.
                    buildUp: _single || _next != null,
                    progress: _progress,
                    onSkip: _skip == null ? null : () => _leave(_skip),
                    onDone: _single ? _close : () => _leave(_next),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One character. A single pull's comes out of its box: you cut the tape,
/// the light of its rarity peeking out of the cut, the box shakes harder
/// the rarer it is, opens, and the card rises out of it towards you. A card
/// of several pulls builds up on its own instead, shaking harder and
/// climbing through the rarities' colours. Then it flips and bursts;
/// legends flash. Its stars pop in one by one. Tap to see it all, then to
/// move on.
class _SingleReveal extends StatefulWidget {
  const _SingleReveal({
    super.key,
    required this.outcome,
    required this.banner,
    required this.boxed,
    required this.buildUp,
    required this.onDone,
    this.owned,
    this.progress,
    this.onSkip,
  });

  final PullOutcome outcome;
  final GachaBanner banner;
  final bool boxed;

  /// The pulled character as you own it now, for its upgrade points.
  final OwnedCard? owned;
  final bool buildUp;
  final VoidCallback onDone;

  /// Which of several pulls this is, e.g. "3 / 10".
  final String? progress;

  /// Skips the rest of several pulls.
  final VoidCallback? onSkip;

  @override
  State<_SingleReveal> createState() => _SingleRevealState();
}

class _SingleRevealState extends State<_SingleReveal> with TickerProviderStateMixin {
  late final _rarity = widget.outcome.card.rarity;
  late final _boxed = widget.boxed && widget.buildUp;
  late final _cut = _TapeCut(() {
    if (!_skipped) sound.boxShakes(_rarity);
    _charge.forward();
  });

  /// The box dropping in and landing.
  late final _land = AnimationController(vsync: this, duration: _landTime);

  /// The camera swaying round the box, and the scissors' hint.
  late final _sway = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  late final _charge = AnimationController(
    vsync: this,
    duration: _boxed ? _boxBuildUpFor(_rarity) : _buildUpFor(_rarity),
  );
  late final _pull = AnimationController(vsync: this, duration: _pullOutTime);
  late final _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  /// How long the tape shows, to cut it as far as the finger goes.
  double _tapeLength = GachaBox.width;

  @override
  void initState() {
    super.initState();
    _charge.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (_boxed && _pull.isDismissed) {
        // It opens with a heavy buzz, heavier the rarer the card.
        if (!_skipped) {
          buzz(openingBuzzFor(_rarity));
          sound
            ..boxOpens(_rarity)
            ..cardRises(_rarity);
        }
        _pull.forward();
      } else if (!_boxed && _flip.isDismissed) {
        _flipCard();
      }
    });
    _pull.addStatusListener((status) {
      if (status == AnimationStatus.completed && _flip.isDismissed) _flipCard();
    });
    _flip.addStatusListener((status) {
      if (status == AnimationStatus.completed && _burst.isDismissed) {
        _sway.stop();
        _burstOut();
      }
    });
    if (_boxed) {
      _sway.repeat();
      _thudOnLanding(_land);
      _land.forward();
    } else {
      _land.value = 1;
      _cut.skip();
      _pull.value = 1;
      if (widget.buildUp) {
        // On its own, the card rumbles as it builds up.
        sound.boxShakes(_rarity);
        _charge.forward();
      } else {
        _charge.value = 1;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _showAll();
  }

  void _flipCard() {
    if (!_skipped && widget.buildUp) sound.cardFlips();
    _flip.forward();
  }

  void _burstOut() {
    if (!_skipped) _revealSound();
    _burst.forward();
  }

  /// The reveal's fanfare, once; not for a card shown again from the
  /// overview.
  bool _revealHeard = false;

  void _revealSound() {
    if (_revealHeard || !widget.buildUp) return;
    _revealHeard = true;
    sound.cardRevealed(_rarity);
  }

  /// Whether everything was shown at once, so without the opening buzz.
  bool _skipped = false;

  void _showAll() {
    _skipped = true;
    // Skipping still ends on the card's fanfare.
    _revealSound();
    _land.value = 1;
    _cut.skip();
    _sway.stop();
    _charge.value = 1;
    _pull.value = 1;
    _flip.value = 1;
    _burst.value = 1;
  }

  /// From the keyboard: cuts the tape once the box is down, then does what
  /// a tap does.
  void advance() {
    if (!_land.isCompleted) return;
    if (_cut.done) return _tap();
    _cut.cutThrough(this, length: () => _tapeLength, changed: () => setState(() {}));
  }

  void _tap() {
    // Swipes cut the tape; taps only skip once it's cut.
    if (!_cut.done) return;
    if (_burst.isCompleted) {
      widget.onDone();
    } else {
      _showAll();
    }
  }

  @override
  void dispose() {
    _cut.dispose();
    _land.dispose();
    _sway.dispose();
    _charge.dispose();
    _pull.dispose();
    _flip.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rarity = _rarity;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      // The tape can be cut once the box has landed.
      onHorizontalDragStart: _cut.done ? null : (_) => setState(() => _cut.cutting = _land.isCompleted),
      onHorizontalDragUpdate: _cut.done
          ? null
          : (details) {
              if (_land.isCompleted) setState(() => _cut.drag(details.delta.dx, _tapeLength));
            },
      onHorizontalDragEnd: _cut.done ? null : (_) => setState(_cut.release),
      child: AnimatedBuilder(
        animation: Listenable.merge([_land, _sway, _charge, _pull, _flip, _burst]),
        builder: (context, _) {
          final charge = _charge.value;
          final burst = _burst.value;
          // Out of a box, white light peeks out of the cut, turning to the
          // rarity's own towards its end; on its own, the card climbs
          // through the rarities' colours up to it.
          final color = _boxed
              ? _peek(_cut.progress, rarity.color)
              : _flip.value >= 0.5
              ? rarity.color
              : _climb(charge, rarity);
          final rise = const Interval(0.2, 0.8).transform(_pull.value);
          // Legends burst out of a white flash.
          final flash = rarity == Rarity.legend && burst > 0
              ? 0.9 * (1 - const Interval(0, 0.35).transform(burst))
              : 0.0;
          final hint = !_cut.done
              ? _cutHint
              : _burst.isCompleted
              ? 'Tap to continue'
              : 'Tap to skip';
          return Stack(
            children: [
              // Opaque, so nothing of a multi-pull underneath shows through.
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
              Positioned.fill(
                child: CustomPaint(
                  painter: _GlowPainter(
                    color: color,
                    intensity: (_boxed ? rise : charge) * 0.5 + burst * 0.5,
                    burst: Curves.easeOut.transform(const Interval(0, 0.6).transform(burst)),
                    sparkle: rarity.stars >= Rarity.hero.stars,
                  ),
                ),
              ),
              Positioned.fill(child: _pull.isCompleted ? Center(child: _card(context, color)) : _outOfTheBox(color)),
              if (flash > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Colors.white.withValues(alpha: flash)),
                  ),
                ),
              if (widget.progress != null || widget.onSkip != null || !_cut.done)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 8,
                  child: Row(
                    children: [
                      Text(
                        widget.progress ?? '',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (widget.onSkip != null || !_cut.done)
                        TextButton(
                          onPressed: widget.onSkip ?? () => setState(_showAll),
                          child: const Text('Skip', style: TextStyle(color: Colors.white)),
                        ),
                    ],
                  ),
                ),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: _burst.isCompleted || !_cut.done ? 1 : 0.4,
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The box: swaying while you cut its tape, shaking once it's cut, the
  /// camera pushing in, then opening, the card rising out of it towards you
  /// as the camera tilts up after it, and the box sinking away.
  Widget _outOfTheBox(Color glow) {
    const cardWidth = 200.0;
    final cut = _cut.progress;
    final charge = _charge.value;
    final pull = _pull.value;
    final open = const Interval(0, 0.3).transform(pull);
    final rise = const Interval(0.2, 0.8, curve: Curves.easeInOutCubic).transform(pull);
    final sink = const Interval(0.55, 1, curve: Curves.easeInCubic).transform(pull);
    final sway = _sway.value;
    // It trembles while you cut, then shakes harder the rarer the card.
    final shake = pull > 0
        ? 0.0
        : (_cut.cutting ? sin(sway * 2 * pi * 90) * (1 + 2 * cut) : 0) + _boxShake(charge, _rarity);
    final pushedIn = _pushedIn(_swaying(sway, shift: Offset(0, 70 + _dropAt(_land.value)), shake: shake), charge);
    final camera = BoxCamera.lerp(
      pushedIn,
      pushedIn.copyWith(yaw: -0.12, pitch: 0.25, zoom: 1.2),
      rise,
    ).copyWith(shift: pushedIn.shift + Offset(0, sink * 700));
    _tapeLength = max(1, GachaBox.tapeLength(camera));
    // Small and deep inside at first, so the walls hide it.
    final startScale = 0.36 * camera.scaleAt((x: 0, y: -GachaBox.height / 2 + 70, z: 0));
    final startAt = GachaBox.inside(camera, below: 70);
    final cardAt = Offset.lerp(startAt, Offset.zero, rise)!;
    final scale = startScale + (1 - startScale) * rise;
    Widget box(GachaBoxLayer layer) => Positioned.fill(
      child: Opacity(
        opacity: 1 - sink,
        child: _box(
          widget.banner,
          camera: camera,
          layer: layer,
          cut: cut,
          open: open,
          leak: _cut.done ? 1 : cut,
          glow: glow,
        ),
      ),
    );
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        box(GachaBoxLayer.back),
        if (pull > 0.2)
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..translateByDouble(cardAt.dx, cardAt.dy, 0, 1)
              // Leaning back as it comes out, then turning to face you.
              ..rotateX((1 - rise) * 0.9)
              ..rotateZ(sin(rise * pi) * 0.12)
              ..scaleByDouble(scale, scale, 1, 1),
            child: CardBack(width: cardWidth, glow: glow),
          ),
        box(GachaBoxLayer.front),
        if (!_cut.done && _land.isCompleted) _scissors(camera, _cut, (sway * 4) % 1),
      ],
    );
  }

  Widget _card(BuildContext context, Color glow) {
    final charge = _charge.value;
    // On its own, the card shakes harder the further the build-up climbs.
    final shake = !_boxed && _flip.value == 0 ? sin(charge * pi * 18) * charge * (1 + _rarity.index * 2.5) : 0.0;
    final grow = _boxed ? 0.0 : 0.06 * charge * (1 - _flip.value);
    final angle = Curves.easeInOut.transform(_flip.value) * pi;
    final showFront = angle > pi / 2;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..translateByDouble(shake, 0, 0, 1)
        ..rotateY(showFront ? angle - pi : angle)
        ..scaleByDouble(1 + grow, 1 + grow, 1, 1),
      child: showFront ? _front(context) : CardBack(width: 200, glow: glow.withValues(alpha: _boxed ? 1 : charge)),
    );
  }

  Widget _front(BuildContext context) {
    final outcome = widget.outcome;
    final card = outcome.card;
    final burst = _burst.value;
    final details = const Interval(0.6, 0.85).transform(burst);
    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: 1 + 0.08 * Curves.elasticOut.transform(burst),
            child: Standee(card: card, width: 200),
          ),
          const SizedBox(height: 12),
          _PoppingStars(rarity: card.rarity, progress: const Interval(0.15, 0.7).transform(burst)),
          const SizedBox(height: 8),
          Nameplate(name: card.subject, title: card.title),
          const SizedBox(height: 12),
          Opacity(
            opacity: details,
            child: Column(
              children: [
                Chip(
                  backgroundColor: outcome.isNew ? card.rarity.color : null,
                  avatar: Icon(outcome.isNew ? Icons.fiber_new_rounded : Icons.upgrade_rounded),
                  label: Text(outcome.isNew ? 'New character!' : 'Duplicate · +1 upgrade point (×${outcome.copies})'),
                ),
                if (!outcome.isNew && (widget.owned?.hasUnspentPoints ?? false))
                  const Chip(
                    backgroundColor: AppPalette.victory,
                    avatar: Icon(Icons.auto_fix_high_rounded, color: Colors.white),
                    label: Text('Upgrade ready!', style: TextStyle(color: Colors.white)),
                  ),
                Text('drawn by ${card.artist}', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A rarity's stars, popping in one after another as [progress] runs.
class _PoppingStars extends StatelessWidget {
  const _PoppingStars({required this.rarity, required this.progress});

  final Rarity rarity;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final count = rarity.stars;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Transform.scale(
            scale: Interval(i / count * 0.7, i / count * 0.7 + 0.3, curve: Curves.easeOutBack).transform(progress),
            child: Icon(
              Icons.star_rounded,
              size: 36,
              color: rarity.color,
              shadows: [Shadow(color: rarity.color, blurRadius: 12)],
            ),
          ),
      ],
    );
  }
}

enum _Stage { cut, buildUp, carousel, reveal, results }

/// Several pulls. You cut their box's tape open once, the light of the
/// rarest pull peeking out of the cut; the box shakes and the camera pushes
/// in like a single pull's, for the rarest pull; the box opens, the cards come out of
/// it one after another and spin into a carousel face down, every back
/// lighting up in its rarity's colour at once, then each one gets a reveal
/// of its own in order, and the overview of them all comes last.
class _MultiPull extends StatefulWidget {
  const _MultiPull({
    super.key,
    required this.outcomes,
    required this.banner,
    required this.owned,
    required this.onReveal,
    required this.onInspect,
    required this.onDone,
  });

  final List<PullOutcome> outcomes;
  final GachaBanner banner;
  final Map<String, OwnedCard> owned;

  /// Reveals one card, then calls `next`; `skip` skips the rest.
  final void Function(PullOutcome outcome, String progress, VoidCallback next, VoidCallback skip) onReveal;
  final ValueChanged<PullOutcome> onInspect;
  final VoidCallback onDone;

  @override
  State<_MultiPull> createState() => _MultiPullState();
}

class _MultiPullState extends State<_MultiPull> with TickerProviderStateMixin {
  /// The camera swaying round the box while you cut, and the scissors'
  /// hint.
  late final _sway = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  /// The box opens, the cards come out of it, spread out and turn once
  /// round while their backs light up.
  late final _carousel = AnimationController(vsync: this, duration: const Duration(milliseconds: 4400));
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  late final _cut = _TapeCut(_buildUp);

  /// The box dropping in and landing.
  late final _land = AnimationController(vsync: this, duration: _landTime);
  var _stage = _Stage.cut;

  /// Once cut, the box shakes like a single pull's, for the rarest pull.
  late final _charge = AnimationController(vsync: this, duration: _boxBuildUpFor(_rarest));
  Timer? _pause;

  /// The rarest of the pulls, whose light peeks out of the cut.
  late final Rarity _rarest = widget.outcomes.map((o) => o.card.rarity).reduce((a, b) => a.index >= b.index ? a : b);

  /// How long the tape shows, to cut it as far as the finger goes.
  double _tapeLength = GachaBox.width;

  @override
  void initState() {
    super.initState();
    _carousel.addStatusListener((status) {
      // A moment to take in the colours before the reveals.
      if (status == AnimationStatus.completed) _pause = Timer(const Duration(milliseconds: 900), _startReveals);
    });
    _charge.addStatusListener((status) {
      if (status == AnimationStatus.completed) _startCarousel();
    });
    _thudOnLanding(_land);
    _land.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toResults();
      });
    }
  }

  void _buildUp() {
    if (!mounted || _stage != _Stage.cut) return;
    setState(() => _stage = _Stage.buildUp);
    sound.boxShakes(_rarest);
    _charge.forward();
  }

  void _startCarousel() {
    if (!mounted || _stage != _Stage.buildUp) return;
    setState(() => _stage = _Stage.carousel);
    // It opens with a heavy buzz, heavier the rarer the best card.
    buzz(openingBuzzFor(_rarest));
    sound
      ..boxOpens(_rarest)
      ..cardRises(_rarest);
    _carousel.forward();
  }

  void _startReveals() {
    if (!mounted || _stage != _Stage.carousel) return;
    _pause?.cancel();
    _sway.stop();
    setState(() => _stage = _Stage.reveal);
    _reveal(0);
  }

  void _reveal(int index) {
    if (!mounted || _stage != _Stage.reveal) return;
    final outcomes = widget.outcomes;
    if (index >= outcomes.length) return _toResults();
    widget.onReveal(outcomes[index], '${index + 1} / ${outcomes.length}', () => _reveal(index + 1), _toResults);
  }

  void _toResults() {
    if (!mounted || _stage == _Stage.results) return;
    _pause?.cancel();
    _land.value = 1;
    _cut.skip();
    _charge.stop();
    _carousel.stop();
    _sway.stop();
    setState(() => _stage = _Stage.results);
  }

  /// From the keyboard: cuts the tape once the box is down, then hurries
  /// along like a tap, and ends the overview like Done.
  void advance() {
    switch (_stage) {
      case _Stage.cut:
        if (_land.isCompleted) _cut.cutThrough(this, length: () => _tapeLength, changed: () => setState(() {}));
      case _Stage.results:
        widget.onDone();
      case _Stage.buildUp || _Stage.carousel || _Stage.reveal:
        _tap();
    }
  }

  /// Hurries the box open and the carousel along; while the tape is whole,
  /// swipes cut it.
  void _tap() {
    if (_stage == _Stage.cut) return;
    if (_stage == _Stage.buildUp) {
      _charge.value = 1;
    } else if (_carousel.isAnimating) {
      _carousel.value = 1;
    } else {
      _startReveals();
    }
  }

  @override
  void dispose() {
    _pause?.cancel();
    _cut.dispose();
    _land.dispose();
    _sway.dispose();
    _charge.dispose();
    _carousel.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final results = _stage == _Stage.results;
    final cutting = _stage == _Stage.cut;
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  results ? 'Your pulls' : '${widget.outcomes.length} pulls',
                  style: textTheme.titleLarge?.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!results)
                TextButton(
                  onPressed: _toResults,
                  child: const Text('Skip', style: TextStyle(color: Colors.white)),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        Expanded(
          child: results
              ? _results()
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _tap,
                  // The tape can be cut once the box has landed.
                  onHorizontalDragStart: cutting ? (_) => setState(() => _cut.cutting = _land.isCompleted) : null,
                  onHorizontalDragUpdate: cutting
                      ? (details) {
                          if (_land.isCompleted) setState(() => _cut.drag(details.delta.dx, _tapeLength));
                        }
                      : null,
                  onHorizontalDragEnd: cutting ? (_) => setState(_cut.release) : null,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_land, _sway, _charge, _carousel, _spin]),
                    builder: (context, _) => _ring(),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: results
              ? FilledButton(onPressed: widget.onDone, child: const Text('Done'))
              : Text(
                  cutting ? _cutHint : 'Tap to hurry',
                  style: TextStyle(color: Colors.white.withValues(alpha: cutting ? 0.7 : 0.6)),
                ),
        ),
      ],
    );
  }

  Widget _ring() {
    final outcomes = widget.outcomes;
    final count = outcomes.length;
    final t = _carousel.value;
    // The box opens and moves down out of the ring's way, the cards rise out
    // of it one after another, and it sinks away once empty.
    final open = const Interval(0, 0.1).transform(t);
    final move = const Interval(0, 0.14, curve: Curves.easeInOut).transform(t);
    double emerge(int i) =>
        Interval(0.08 + 0.2 * i / count, 0.22 + 0.2 * i / count, curve: Curves.easeOutCubic).transform(t);
    final sink = const Interval(0.34, 0.46, curve: Curves.easeInCubic).transform(t);
    final spread = const Interval(0.12, 0.47, curve: Curves.easeOutBack).transform(t);
    // One turn round, slowing down until the first card is at the front.
    final position = -count * (1 - Curves.easeOutCubic.transform(t));
    // All backs light up together, then pulse gently.
    final glow = const Interval(0.3, 0.7, curve: Curves.easeIn).transform(t);
    final pulse = 0.85 + 0.15 * sin(_spin.value * 2 * pi * 6);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The ring is about 3.5 cards wide, so it fits the screen.
        final width = min(140.0, min(constraints.maxWidth * 0.26, constraints.maxHeight * 0.5 / 1.45));
        final radius = width * 1.6 * spread;
        double angle(int i) => 2 * pi * (i - position) / count;
        // Back cards first, so the front one is drawn on top.
        final order = [for (var i = 0; i < count; i++) i]..sort((a, b) => cos(angle(a)).compareTo(cos(angle(b))));
        // Big in the middle while you cut, then small below the ring.
        final fit = min(1.0, constraints.maxWidth / 360);
        // It trembles while you cut, then shakes like a single pull's until it opens.
        final shake =
            (_cut.cutting ? sin(_sway.value * 2 * pi * 90) * (1 + 2 * _cut.progress) : 0.0) +
            (t == 0 ? _boxShake(_charge.value, _rarest) : 0.0);
        final swaying = _pushedIn(
          _swaying(_sway.value, zoom: fit, shift: Offset(0, 20 + _dropAt(_land.value)), shake: shake),
          _charge.value,
        );
        final camera =
            BoxCamera.lerp(
              swaying,
              swaying.copyWith(zoom: fit * 0.7, pitch: 0.5, shift: Offset(0, constraints.maxHeight / 2 - 90 * fit)),
              move,
            ).copyWith(
              shift:
                  Offset.lerp(swaying.shift, Offset(0, constraints.maxHeight / 2 - 90 * fit), move)! +
                  Offset(0, sink * constraints.maxHeight),
            );
        _tapeLength = max(1, GachaBox.tapeLength(camera));
        final from = GachaBox.inside(camera, below: 60);
        final fromScale = 0.4 * camera.scaleAt((x: 0, y: -GachaBox.height / 2 + 60, z: 0));
        Widget box(GachaBoxLayer layer) => Positioned.fill(
          child: Opacity(
            opacity: 1 - sink,
            child: _box(
              widget.banner,
              camera: camera,
              layer: layer,
              cut: _cut.progress,
              open: open,
              leak: _cut.done ? 1 - glow * 0.5 : _cut.progress,
              glow: _peek(_cut.progress, _rarest.color),
            ),
          ),
        );
        // Just the dark background, so the glows stand out. It fills the
        // space, so swipes anywhere cut the tape.
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (sink < 1) box(GachaBoxLayer.back),
              for (final i in order)
                if (emerge(i) > 0)
                  Transform.translate(
                    // From deep in the box up into the ring, growing as it
                    // comes towards you.
                    offset: Offset.lerp(from, Offset.zero, emerge(i))!,
                    child: Transform.scale(
                      scale: fromScale + (1 - fromScale) * emerge(i),
                      child: _ringCard(outcomes[i], width: width, angle: angle(i), radius: radius, glow: glow * pulse),
                    ),
                  ),
              if (sink < 1) box(GachaBoxLayer.front),
              if (_stage == _Stage.cut && _land.isCompleted) _scissors(camera, _cut, (_sway.value * 4) % 1),
            ],
          ),
        );
      },
    );
  }

  Widget _ringCard(
    PullOutcome outcome, {
    required double width,
    required double angle,
    required double radius,
    required double glow,
  }) {
    final facing = cos(angle);
    // Cards at the back fade into the dark, darkened rather than see-through
    // so the ones behind them don't show through.
    return ColorFiltered(
      colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.7 * (1 - facing) / 2), BlendMode.srcATop),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          // Seen from a little above, so the ring's far side rises.
          ..rotateX(0.45)
          ..translateByDouble(sin(angle) * radius, 0, radius * (1 - facing), 1)
          ..rotateY(angle),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Only the glow tells the rarity, never the character.
            CardBack(
              width: width,
              glow: outcome.card.rarity.color.withValues(alpha: glow.clamp(0.0, 1.0)),
            ),
            StandeeBase(width: width * 0.62),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    final outcomes = widget.outcomes;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        const labels = 52.0;
        final count = outcomes.length;
        final columns = min(count, 5);
        final rows = (count / columns).ceil();
        final width = min(
          min(104.0, (constraints.maxWidth - 32 - (columns - 1) * gap) / columns),
          // Standees are a little taller than wide, plus their labels.
          ((constraints.maxHeight - 32 - (rows - 1) * gap) / rows - labels) / 1.45,
        );
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (i, outcome) in outcomes.indexed)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 300 + i * 60),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) => Transform.scale(scale: value, child: child),
                    child: GestureDetector(
                      onTap: () => widget.onInspect(outcome),
                      child: SizedBox(
                        width: width,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Standee(card: outcome.card, width: width),
                            StarRow(rarity: outcome.card.rarity, size: 14),
                            Text(
                              outcome.card.subject,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              outcome.isNew
                                  ? 'NEW'
                                  : widget.owned[outcome.card.id]?.hasUnspentPoints ?? false
                                  ? 'Upgrade ready!'
                                  : '+1 upgrade',
                              style: TextStyle(
                                color: outcome.isNew ? outcome.card.rarity.color : Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A soft glow in the rarity's colour behind a reveal, and the ring (and
/// for rare ones the sparkles) it bursts into.
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.color, required this.intensity, required this.burst, required this.sparkle});

  final Color color;
  final double intensity;
  final double burst;
  final bool sparkle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      size.shortestSide * (0.2 + 0.25 * intensity),
      Paint()
        ..color = color.withValues(alpha: 0.6 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );
    if (burst > 0 && burst < 1) {
      canvas.drawCircle(
        center,
        size.shortestSide * 0.6 * burst,
        Paint()
          ..color = color.withValues(alpha: 1 - burst)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * (1 - burst),
      );
      if (sparkle) {
        final random = Random(7);
        final dot = Paint()..color = Colors.white.withValues(alpha: 1 - burst);
        for (var i = 0; i < 40; i++) {
          final a = random.nextDouble() * 2 * pi;
          final d = size.shortestSide * (0.15 + random.nextDouble() * 0.5) * burst;
          canvas.drawCircle(center + Offset(cos(a), sin(a)) * d, 2 + random.nextDouble() * 3, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.intensity != intensity ||
      oldDelegate.burst != burst ||
      oldDelegate.sparkle != sparkle;
}
