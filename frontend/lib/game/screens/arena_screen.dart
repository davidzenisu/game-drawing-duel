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

/// The Arena ([Arena]): two of last week's challengers on one big card, and
/// you pick the better drawing, whatever their boosts were. Drag the card
/// toward it (left for the left one, right for the right one) and let go:
/// it flies off that way and the next matchup comes up. On a computer, ← and
/// → throw it the same way. "Can't decide" (or ↓) is a draw: the card drops.
/// The artists stay hidden, and you never get a drawing of your own. Today's
/// first [ArenaStatus.pack] votes earn [ArenaStatus.packStars] stars; you can
/// go on, unrewarded, up to today's cap.
class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

/// How the current matchup was decided.
enum _Pick { first, second, draw }

class _ArenaScreenState extends State<ArenaScreen> with SingleTickerProviderStateMixin {
  GameSession get controller => widget.controller;

  ArenaRound? _round;
  bool _loading = true;
  bool _voting = false;

  /// Where the card is: dragged by the finger, or on its way back or out.
  Offset _offset = Offset.zero;
  late final AnimationController _motion;
  Tween<Offset> _path = Tween(begin: Offset.zero, end: Offset.zero);

  /// The width of the card, which the drag is measured against.
  double _cardWidth = 400;

  static const _flyTime = Duration(milliseconds: 280);

  /// The share of the card's width a drag must pass to pick a side.
  static const _threshold = 0.22;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: _flyTime)
      ..addListener(() => setState(() => _offset = _path.transform(Curves.easeOutCubic.transform(_motion.value))));
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final round = await runGameQuery(context, controller.arenaRound);
    if (!mounted) return;
    setState(() {
      _round = round ?? _round;
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
      _vote(_Pick.first);
    } else if (_lean >= 1 || flung > 900) {
      _vote(_Pick.second);
    } else {
      _animateTo(Offset.zero);
    }
  }

  Future<void> _vote(_Pick pick) async {
    final matchup = _round?.matchup;
    if (matchup == null || _voting) return;
    final (first, second) = matchup;
    final rewardedBefore = _round?.status?.rewarded ?? false;
    setState(() => _voting = true);
    GameSound.instance.buttonConfirm();
    // The card flies off toward the pick (or drops, for a draw) while the
    // vote is sent.
    final away = _cardWidth * 1.6;
    final flight = _animateTo(switch (pick) {
      _Pick.first => Offset(-away, _offset.dy + 40),
      _Pick.second => Offset(away, _offset.dy + 40),
      _Pick.draw => Offset(0, away),
    });
    final round = await runGameQuery(
      context,
      () => controller.arenaVote(
        first,
        second,
        winner: switch (pick) {
          _Pick.first => first,
          _Pick.second => second,
          _Pick.draw => null,
        },
      ),
    );
    await flight;
    if (!mounted) return;
    if (round?.status?.rewarded == true && !rewardedBefore) GameSound.instance.reward();
    _motion.reset();
    setState(() {
      _round = round ?? _round;
      _voting = false;
      _offset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    final canPick = round?.matchup != null && !_voting;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => KeyControls(
        onLeft: canPick ? () => _vote(_Pick.first) : null,
        onRight: canPick ? () => _vote(_Pick.second) : null,
        onDown: canPick ? () => _vote(_Pick.draw) : null,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Arena'),
            actions: [
              TicketChip(tickets: controller.tickets, stars: controller.stars),
              const SizedBox(width: 12),
            ],
          ),
          body: ThemedBackground(
            theme: controller.theme,
            child: SafeArea(
              child: _loading && round == null
                  ? const Center(child: CircularProgressIndicator())
                  : _body(context, round),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ArenaRound? round) {
    final status = round?.status;
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
    final matchup = round!.matchup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _StatusBar(status: status, week: controller.weekOf(status.week)),
            ),
          ),
        ),
        Expanded(
          child: matchup == null
              ? _Message(
                  icon: status.canVote ? Icons.done_all_rounded : Icons.bedtime_rounded,
                  title: status.canVote ? 'Every matchup voted on' : "That's all for today",
                  text: status.canVote
                      ? 'You voted on every matchup of this Arena. Its winners are crowned on Monday.'
                      : 'Come back tomorrow for more matchups. The Arena runs until Sunday; its winners are '
                            'crowned on Monday.',
                )
              : LayoutBuilder(builder: (context, constraints) => _deck(context, matchup, status, constraints)),
        ),
        if (matchup != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _ScenicHint(
                    dark: controller.theme.isDark,
                    text: showsPagerArrows(context) ? '← or drag left' : 'Drag left',
                  ),
                ),
                const SizedBox(width: 12),
                _CantDecideButton(onPressed: _voting ? null : () => _vote(_Pick.draw)),
                const SizedBox(width: 12),
                Flexible(
                  child: _ScenicHint(
                    dark: controller.theme.isDark,
                    text: showsPagerArrows(context) ? 'Drag right or →' : 'Drag right',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The matchup's card, as big as the space allows, over a blank one when
  /// more matchups are to come today.
  Widget _deck(BuildContext context, (CharacterCard, CharacterCard) matchup, ArenaStatus status, BoxConstraints space) {
    const pad = 12.0;
    final size = _MatchupCard.sizeFor(Size(space.maxWidth - 2 * pad, space.maxHeight - 2 * pad));
    _cardWidth = size.width;
    final lean = _lean.clamp(-1.0, 1.0);
    final card = _MatchupCard(
      key: ValueKey('${matchup.$1.id}-${matchup.$2.id}'),
      size: size,
      first: matchup.$1,
      second: matchup.$2,
      lean: lean,
    );
    return Center(
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The next card waiting below, once this one is on its way.
            if (status.votesToday + 1 < status.cap)
              Positioned.fill(
                child: Transform.scale(
                  scale: 0.94 + 0.06 * min(1.0, _offset.distance / _cardWidth),
                  child: const _BlankCard(),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('arena-card'),
                onPanUpdate: _voting ? null : (details) => setState(() => _offset += details.delta),
                onPanEnd: _voting ? null : _onDragEnd,
                child: Transform.translate(
                  offset: _offset,
                  child: Transform.rotate(angle: _offset.dx / _cardWidth * 0.25, child: card),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/// The matchup: both challengers side by side on one card, each drawing as
/// big as it fits, with who it portrays and its title below. The side the
/// card leans toward lights up, the other one dims.
class _MatchupCard extends StatelessWidget {
  const _MatchupCard({super.key, required this.size, required this.first, required this.second, required this.lean});

  final Size size;
  final CharacterCard first;
  final CharacterCard second;

  /// -1 (all the way to the left one) to 1 (the right one).
  final double lean;

  static const _padding = 10.0;
  static const _gap = 10.0;
  static const _labels = 50.0;
  static const _maxWidth = 960.0;

  /// The biggest card that fits [space].
  static Size sizeFor(Size space) {
    final width = min(space.width, _maxWidth);
    // Two drawings side by side, each [cardAspectRatio].
    double heightFor(double width) => (width - 2 * _padding - _gap) / 2 / cardAspectRatio + 2 * _padding + _labels;
    if (heightFor(width) <= space.height) return Size(width, heightFor(width));
    final drawing = max(40.0, space.height - 2 * _padding - _labels) * cardAspectRatio;
    return Size(2 * drawing + 2 * _padding + _gap, space.height);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: colors.surfaceContainerLow,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(_padding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Side(card: first, glow: max(0, -lean), dim: max(0, lean)),
            ),
            const SizedBox(width: _gap),
            Expanded(
              child: _Side(card: second, glow: max(0, lean), dim: max(0, -lean)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One challenger of the matchup.
class _Side extends StatelessWidget {
  const _Side({required this.card, required this.glow, required this.dim});

  final CharacterCard card;

  /// How much the card leans toward it, and away from it: 0 to 1.
  final double glow;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '${card.subject}, ${card.title}',
      child: Opacity(
        opacity: 1 - 0.5 * dim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: cardAspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
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
              ),
            ),
            const SizedBox(height: 6),
            Text(
              card.subject,
              style: textTheme.titleSmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              card.title,
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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

/// The next matchup's card, face down below the current one.
class _BlankCard extends StatelessWidget {
  const _BlankCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: Center(child: Icon(Icons.stadium_rounded, size: 64, color: colors.outlineVariant)),
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
