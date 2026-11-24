import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../sound.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/key_controls.dart';
import '../widgets/sketch_canvas.dart';
import '../widgets/themed_background.dart';
import '../widgets/ticket_chip.dart';

/// The Arena ([Arena]): two of last week's challengers face off on one tall
/// card, split by a curved line like a versus screen: one stands top right,
/// its nameplate across the line on the left; the other stands bottom left,
/// its nameplate on the right. You pick the better drawing, whatever their
/// boosts were: drag the card right for the one on the right, left for the
/// one on the left, and let go; it flies off and the next matchup, already
/// waiting below, comes up. On a computer, → and ← throw it the same way.
/// "Can't decide" (or ↓) is a draw: the card drops. The artists stay hidden,
/// and you never get a drawing of your own. Today's first
/// [ArenaStatus.pack] votes earn [ArenaStatus.packStars] stars; you can go
/// on, unrewarded, up to today's cap.
class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

/// How a matchup was decided: for the one on the right (top), the one on the
/// left (bottom), or a draw.
enum _Pick { right, left, draw }

typedef _Matchup = (CharacterCard, CharacterCard);

class _ArenaScreenState extends State<ArenaScreen> with TickerProviderStateMixin {
  GameSession get controller => widget.controller;

  ArenaStatus? _status;
  bool _loading = true;
  bool _voting = false;

  /// The matchup on top, and the one waiting below it.
  _Matchup? _current;
  _Matchup? _next;

  /// Where the card on top is: dragged by the finger, or on its way back or
  /// out.
  Offset _offset = Offset.zero;
  late final AnimationController _motion;

  /// The challengers' hovering, round and round.
  late final AnimationController _hover;
  Tween<Offset> _path = Tween(begin: Offset.zero, end: Offset.zero);

  /// The size of the card, which the drag is measured against.
  double _cardWidth = 400;

  static const _flyTime = Duration(milliseconds: 280);

  /// The share of the card's width a drag must pass to pick a side.
  static const _threshold = 0.22;

  @override
  void initState() {
    super.initState();
    _hover = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
    _motion = AnimationController(vsync: this, duration: _flyTime)
      ..addListener(() => setState(() => _offset = _path.transform(Curves.easeOutCubic.transform(_motion.value))));
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _hover.dispose();
    _motion.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final round = await runGameQuery(context, controller.arenaRound);
    if (!mounted) return;
    setState(() {
      if (round != null) {
        _status = round.status;
        _current = round.matchup;
        _next = round.next;
      }
      _loading = false;
    });
  }

  /// How far the card leans to the left (negative) or right (positive), as a
  /// share of the threshold: past ±1 a drag picks that side.
  double get _lean => _offset.dx / (_cardWidth * _threshold);

  Future<void> _animateTo(Offset end) {
    _path = Tween(begin: _offset, end: end);
    return _motion.forward(from: 0);
  }

  void _onDragEnd(DragEndDetails details) {
    final flung = details.velocity.pixelsPerSecond.dx;
    if (_lean <= -1 || flung < -900) {
      _vote(_Pick.left);
    } else if (_lean >= 1 || flung > 900) {
      _vote(_Pick.right);
    } else {
      _animateTo(Offset.zero);
    }
  }

  Future<void> _vote(_Pick pick) async {
    final matchup = _current;
    if (matchup == null || _voting) return;
    // The first stands on the right, the second on the left.
    final (right, left) = matchup;
    final rewardedBefore = _status?.rewarded ?? false;
    setState(() => _voting = true);
    GameSound.instance.buttonConfirm();
    // The card flies off toward the pick (or drops, for a draw) while the
    // vote is sent; the next one is already below.
    final away = _cardWidth * 1.8;
    final flight = _animateTo(switch (pick) {
      _Pick.left => Offset(-away, _offset.dy + 60),
      _Pick.right => Offset(away, _offset.dy + 60),
      _Pick.draw => Offset(0, away),
    });
    final round = await runGameQuery(
      context,
      () => controller.arenaVote(
        right,
        left,
        winner: switch (pick) {
          _Pick.right => right,
          _Pick.left => left,
          _Pick.draw => null,
        },
      ),
    );
    await flight;
    if (!mounted) return;
    if (round?.status?.rewarded == true && !rewardedBefore) GameSound.instance.reward();
    _motion.reset();
    setState(() {
      _offset = Offset.zero;
      _voting = false;
      if (round == null) return; // The vote failed: the same card again.
      _status = round.status;
      final canVote = round.status?.canVote ?? false;
      // The card that waited below comes up; after it, whichever the server
      // picks next that isn't it.
      final waiting = _next;
      _current = !canVote ? null : (waiting ?? round.matchup);
      _next = !canVote || _current == null
          ? null
          : samePair(round.matchup, _current)
          ? round.next
          : round.matchup;
      if (round.status != null && round.status!.votesToday + 1 >= round.status!.cap) _next = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canPick = _current != null && !_voting;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => KeyControls(
        onLeft: canPick ? () => _vote(_Pick.left) : null,
        onRight: canPick ? () => _vote(_Pick.right) : null,
        onDown: canPick ? () => _vote(_Pick.draw) : null,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Arena'),
            actions: [
              TicketChip(tickets: controller.tickets, stars: controller.stars),
              const SizedBox(width: 12),
            ],
          ),
          // A plain page: the card brings its own sceneries.
          body: SafeArea(
            child: _loading && _status == null ? const Center(child: CircularProgressIndicator()) : _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final status = _status;
    if (status == null) {
      return _Message(
        icon: Icons.stadium_rounded,
        title: 'The Arena opens next week',
        text: controller.server.isSpeed
            ? 'Speed mode has no Arena.'
            : "Once this week is over, the Arena opens with this week's challengers, but its weekly heroes: "
                  'everyone votes on them for a week, and the top ${Arena.maxWinners} become Arena winners.',
      );
    }
    final current = _current;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final keys = showsPagerArrows(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _StatusBar(status: status, week: controller.weekOf(status.week)),
            ),
          ),
        ),
        Expanded(
          child: current == null
              ? _Message(
                  icon: status.canVote ? Icons.done_all_rounded : Icons.bedtime_rounded,
                  title: status.canVote ? 'Every matchup voted on' : "That's all for today",
                  text: status.canVote
                      ? 'You voted on every matchup of this Arena. Its winners are crowned on Monday.'
                      : 'Come back tomorrow for more matchups. The Arena runs until Sunday; its winners are '
                            'crowned on Monday.',
                )
              : LayoutBuilder(
                  builder: (context, constraints) => AnimatedBuilder(
                    animation: _hover,
                    builder: (context, _) => _deck(
                      current,
                      constraints,
                      // Still, for players who turned animations off.
                      MediaQuery.disableAnimationsOf(context) ? 0 : _hover.value,
                    ),
                  ),
                ),
        ),
        if (current != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _ScenicHint(dark: dark, text: keys ? '← or drag left' : '← Drag left'),
                ),
                const SizedBox(width: 12),
                _CantDecideButton(onPressed: _voting ? null : () => _vote(_Pick.draw)),
                const SizedBox(width: 12),
                Flexible(
                  child: _ScenicHint(dark: dark, text: keys ? 'Drag right or →' : 'Drag right →'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The matchup's card, as big as the space allows, over the next one; both
  /// with their challengers at [hover] (0 to 1 and round again).
  Widget _deck(_Matchup current, BoxConstraints space, double hover) {
    const pad = 8.0;
    final size = _VersusCard.sizeFor(Size(space.maxWidth - 2 * pad, space.maxHeight - 2 * pad));
    _cardWidth = size.width;
    final next = _next;
    // The card below grows into place as the one on top goes.
    final rise = min(1.0, _offset.distance / _cardWidth);
    return Center(
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (next != null)
              Positioned.fill(
                // Tilted a little, so it peeks out from behind; it
                // straightens as the one on top goes.
                child: Transform.rotate(
                  angle: 0.045 * (1 - rise),
                  child: Transform.scale(
                    scale: 0.97 + 0.03 * rise,
                    child: _VersusCard(key: ValueKey(_pairKey(next)), size: size, matchup: next, lean: 0, hover: hover),
                  ),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('arena-card'),
                onPanUpdate: _voting ? null : (details) => setState(() => _offset += details.delta),
                onPanEnd: _voting ? null : _onDragEnd,
                child: Transform.translate(
                  offset: _offset,
                  child: Transform.rotate(
                    angle: _offset.dx / _cardWidth * 0.25,
                    child: _VersusCard(
                      key: ValueKey(_pairKey(current)),
                      size: size,
                      matchup: current,
                      lean: _lean.clamp(-1.0, 1.0),
                      hover: hover,
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

  static String _pairKey(_Matchup m) => '${m.$1.id}-${m.$2.id}';
}

/// Today's votes in one line: the pack and its stars, or what's left today.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.status, required this.week});

  final ArenaStatus status;

  /// The week of its challengers.
  final int week;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final packDone = status.rewarded || status.votesToday >= status.pack;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.stadium_rounded, size: 18, color: AppPalette.rarityLegend),
                const SizedBox(width: 6),
                Expanded(
                  child: Text("Week $week's challengers", style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    packDone
                        ? status.canVote
                              ? '${status.packStars} ★ earned · ${status.cap - status.votesToday} more today'
                              : '${status.packStars} ★ earned · done for today'
                        : '${status.votesToday} of ${status.pack} for ${status.packStars} ★',
                    style: textTheme.labelLarge,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: packDone
                    ? (status.cap == 0 ? 1 : status.votesToday / status.cap)
                    : (status.votesToday / status.pack).clamp(0.0, 1.0),
                minHeight: 6,
                color: packDone ? AppPalette.victory : AppPalette.star,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A matchup as a versus card, split from top left to bottom right along a
/// soft curve: each half shows the scenery of its challenger's day. The
/// first challenger stands top right, its nameplate beside it on the left,
/// as in a fight; the second stands bottom left, its nameplate on the
/// right. Both drawings hover gently over their bases ([hover], 0 to 1 and
/// round again). The side the card leans toward lights up with a "BETTER"
/// stamp, the other dims.
class _VersusCard extends StatelessWidget {
  const _VersusCard({super.key, required this.size, required this.matchup, required this.lean, this.hover = 0});

  final Size size;
  final _Matchup matchup;

  /// -1 (all the way to the left one) to 1 (the right one).
  final double lean;

  /// Where the hovering is, 0 to 1 and round again.
  final double hover;

  static const _padding = 12.0;
  static const _maxWidth = 560.0;

  /// A standee's height for its width: the drawing and its base.
  static const _standeeHeight = 1 / cardAspectRatio + 0.62 * 0.32;

  /// The biggest card that fits [space]: as wide as it can be, and at most
  /// twice as tall as wide; never so flat that the two standees won't fit
  /// one above the other.
  static Size sizeFor(Size space) {
    var width = min(space.width, _maxWidth);
    final height = min(space.height, width * 2);
    // The standees take up most of the height, the nameplates beside them.
    width = min(width, height / 1.35);
    return Size(width, height);
  }

  /// The width of each drawing in a card of [size].
  static double drawingWidth(Size size) =>
      min(size.width * 0.58, (size.height - 2 * _padding) / (2 * _standeeHeight + 0.08));

  @override
  Widget build(BuildContext context) {
    final (right, left) = matchup;
    final drawing = drawingWidth(size);
    final plate = size.width - drawing - 2 * _padding - 8;
    final standee = drawing * _standeeHeight;
    // How far a drawing rises above its base, out of step with the other.
    // How far a standee sways to either side, out of step with the other.
    double sway(double phase) => drawing * 0.04 * sin(2 * pi * (hover + phase));
    return Material(
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: _Half(right: true),
              child: _Scenery(card: right, glow: max(0, lean)),
            ),
          ),
          Positioned.fill(
            child: ClipPath(
              clipper: _Half(right: false),
              child: _Scenery(card: left, glow: max(0, -lean)),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _SeamPainter())),
          ),
          // The one on the right, top, with its nameplate on the left.
          Positioned(
            right: _padding,
            top: _padding,
            width: drawing,
            child: _Contender(card: right, width: drawing, glow: max(0, lean), dim: max(0, -lean), sway: sway(0)),
          ),
          Positioned(
            left: _padding,
            top: _padding + standee * 0.12,
            width: plate,
            child: _Plate(card: right, dim: max(0, -lean), large: size.width > 420),
          ),
          // The one on the left, bottom, with its nameplate on the right.
          Positioned(
            left: _padding,
            bottom: _padding,
            width: drawing,
            child: _Contender(card: left, width: drawing, glow: max(0, -lean), dim: max(0, lean), sway: sway(0.5)),
          ),
          Positioned(
            right: _padding,
            bottom: _padding + standee * 0.3,
            width: plate,
            child: _Plate(card: left, dim: max(0, lean), large: size.width > 420),
          ),
        ],
      ),
    );
  }
}

/// The curve that splits the versus card, from top left to bottom right.
Path _seam(Size size) => Path()
  ..moveTo(size.width * 0.1, -2)
  ..cubicTo(
    size.width * 0.35,
    size.height * 0.3,
    size.width * 0.5,
    size.height * 0.55,
    size.width * 0.62,
    size.height * 0.75,
  )
  ..quadraticBezierTo(size.width * 0.72, size.height * 0.9, size.width * 0.8, size.height + 2);

/// One half of the versus card: right of the seam (top right) or left of it
/// (bottom left).
class _Half extends CustomClipper<Path> {
  const _Half({required this.right});

  final bool right;

  @override
  Path getClip(Size size) {
    final x = right ? size.width + 2 : -2.0;
    return Path.from(_seam(size))
      ..lineTo(x, size.height + 2)
      ..lineTo(x, -2)
      ..close();
  }

  @override
  bool shouldReclip(_Half old) => old.right != right;
}

/// The seam between the two sceneries: a faint, soft light.
class _SeamPainter extends CustomPainter {
  const _SeamPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _seam(size),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(_SeamPainter old) => false;
}

/// The scenery of a challenger's day, warmed up as the card leans toward it.
class _Scenery extends StatelessWidget {
  const _Scenery({required this.card, required this.glow});

  final CharacterCard card;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      theme: card.scenery,
      child: ColoredBox(color: AppPalette.rarityLegend.withValues(alpha: 0.25 * glow)),
    );
  }
}

/// A challenger of the matchup: its drawing on its standee base, the two
/// swaying together [sway] to the side, leaning into it a little.
class _Contender extends StatelessWidget {
  const _Contender({
    required this.card,
    required this.width,
    required this.glow,
    required this.dim,
    required this.sway,
  });

  final CharacterCard card;
  final double width;

  /// How much the card leans toward it, and away from it: 0 to 1.
  final double glow;
  final double dim;

  /// How far the standee sways to the right (negative: to the left).
  final double sway;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${card.subject}, ${card.title}',
      child: Transform.translate(
        offset: Offset(sway, 0),
        child: Transform.rotate(
          angle: sway / width * 0.35,
          alignment: Alignment.bottomCenter,
          child: _Dimmed(
            dim: dim,
            radius: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: width,
                  height: width / cardAspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 4),
                            ),
                            if (glow > 0)
                              BoxShadow(
                                color: AppPalette.rarityLegend.withValues(alpha: 0.7 * glow),
                                blurRadius: 24 * glow,
                                spreadRadius: 4 * glow,
                              ),
                          ],
                        ),
                        child: CardboardCard(child: SketchView(card.sketch)),
                      ),
                      if (glow > 0)
                        Align(
                          alignment: const Alignment(0, -0.75),
                          child: Opacity(opacity: glow, child: const _Stamp()),
                        ),
                    ],
                  ),
                ),
                StandeeBase(width: width * 0.62),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] darkened as the card leans away from it ([dim], 0 to 1): a shade
/// over it rather than see-through, so the scenery doesn't show through.
class _Dimmed extends StatelessWidget {
  const _Dimmed({required this.dim, required this.radius, required this.child});

  final double dim;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (dim <= 0) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.4 * dim), BlendMode.srcATop),
      child: child,
    );
  }
}

/// A challenger's nameplate beside it, as in a fight: who it portrays, then
/// its title. Without its rarity's stars, as the Arena judges the drawing
/// only.
class _Plate extends StatelessWidget {
  const _Plate({required this.card, required this.dim, required this.large});

  final CharacterCard card;
  final double dim;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return _Dimmed(
      dim: dim,
      radius: large ? 16 : 10,
      child: Nameplate(name: card.subject, title: card.title, nameFirst: true, large: large),
    );
  }
}

/// "BETTER", stamped on the side the card leans toward.
class _Stamp extends StatelessWidget {
  const _Stamp();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          border: Border.all(color: AppPalette.rarityLegend, width: 3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'BETTER',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFFB36B00),
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

/// "Can't decide": a solid, raised button, so it reads on any scenery.
class _CantDecideButton extends StatelessWidget {
  const _CantDecideButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 4,
        shadowColor: Colors.black54,
        side: BorderSide(color: colors.outline),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      icon: const Icon(Icons.balance_rounded),
      label: const Text("Can't decide"),
    );
  }
}

/// A short hint right on the scenery, in a color that follows its
/// brightness.
class _ScenicHint extends StatelessWidget {
  const _ScenicHint({required this.dark, required this.text});

  final bool dark;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: dark ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w700,
        shadows: [Shadow(color: dark ? Colors.black45 : Colors.white70, blurRadius: 4)],
      ),
    );
  }
}

/// A message instead of a matchup.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: AppPalette.rarityLegend),
                const SizedBox(height: 12),
                Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(text, style: textTheme.bodyMedium, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
