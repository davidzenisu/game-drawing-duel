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

/// The Arena ([Arena]): two of last week's challengers side by side, and
/// you pick the better drawing, whatever their boosts were: swipe toward it,
/// tap it, or press ← / →; "Can't decide" (or ↓) is a draw. Their artists
/// stay hidden, and you never get a drawing of your own. Today's first
/// [ArenaStatus.pack] votes earn [ArenaStatus.packStars] stars; you can go
/// on, unrewarded, up to today's cap.
class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

/// How the current matchup was decided, while it animates out.
enum _Pick { first, second, draw }

class _ArenaScreenState extends State<ArenaScreen> {
  GameSession get controller => widget.controller;

  ArenaRound? _round;
  bool _loading = true;
  bool _voting = false;
  _Pick? _picked;

  /// How far the matchup is dragged sideways, for the swipe.
  double _drag = 0;

  static const _swipeDistance = 80.0;

  @override
  void initState() {
    super.initState();
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final round = await runGameQuery(context, controller.arenaRound);
    if (!mounted) return;
    setState(() {
      _round = round ?? _round;
      _loading = false;
    });
  }

  Future<void> _vote(_Pick pick) async {
    final matchup = _round?.matchup;
    if (matchup == null || _voting) return;
    final (first, second) = matchup;
    final rewardedBefore = _round?.status?.rewarded ?? false;
    setState(() {
      _voting = true;
      _picked = pick;
      _drag = 0;
    });
    GameSound.instance.buttonConfirm();
    // Long enough to see the pick before the next matchup comes in.
    final shown = Future<void>.delayed(const Duration(milliseconds: 350));
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
    await shown;
    if (!mounted) return;
    if (round?.status?.rewarded == true && !rewardedBefore) GameSound.instance.reward();
    setState(() {
      _round = round ?? _round;
      _voting = false;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    final matchup = round?.matchup;
    final canPick = matchup != null && !_voting;
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
            child: _loading && round == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _content(context, round),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, ArenaRound? round) {
    final status = round?.status;
    if (status == null) {
      return [
        _Message(
          icon: Icons.stadium_rounded,
          title: 'The Arena opens next week',
          text: controller.server.isSpeed
              ? 'Speed mode has no Arena.'
              : "Once this week is over, the Arena opens with this week's challengers, but its weekly heroes: "
                    'everyone votes on them for a week, and the top ${Arena.maxWinners} become Arena winners.',
        ),
      ];
    }
    final matchup = round!.matchup;
    return [
      _StatusCard(status: status, week: controller.weekOf(status.week)),
      const SizedBox(height: 16),
      if (matchup == null)
        _Message(
          icon: status.canVote ? Icons.done_all_rounded : Icons.bedtime_rounded,
          title: status.canVote ? 'Every matchup voted on' : "That's all for today",
          text: status.canVote
              ? 'You voted on every matchup of this Arena. Its winners are crowned on Monday.'
              : 'Come back tomorrow for more matchups. The Arena runs until Sunday; its winners are crowned on '
                    'Monday.',
        )
      else ...[
        Text(
          'Which one is the better drawing?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: controller.theme.isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onHorizontalDragUpdate: _voting ? null : (details) => setState(() => _drag += details.delta.dx),
          onHorizontalDragEnd: _voting
              ? null
              : (_) {
                  final drag = _drag;
                  if (drag <= -_swipeDistance) {
                    _vote(_Pick.first);
                  } else if (drag >= _swipeDistance) {
                    _vote(_Pick.second);
                  } else {
                    setState(() => _drag = 0);
                  }
                },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Contender(
                  key: ValueKey('first-${matchup.$1.id}'),
                  card: matchup.$1,
                  // Swiping left leans toward the left one.
                  lean: (-_drag / _swipeDistance).clamp(0.0, 1.0),
                  picked: _picked == null ? null : _picked == _Pick.first,
                  draw: _picked == _Pick.draw,
                  onTap: _voting ? null : () => _vote(_Pick.first),
                  hint: '← or swipe left',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Contender(
                  key: ValueKey('second-${matchup.$2.id}'),
                  card: matchup.$2,
                  lean: (_drag / _swipeDistance).clamp(0.0, 1.0),
                  picked: _picked == null ? null : _picked == _Pick.second,
                  draw: _picked == _Pick.draw,
                  onTap: _voting ? null : () => _vote(_Pick.second),
                  hint: '→ or swipe right',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: _voting ? null : () => _vote(_Pick.draw),
            icon: const Icon(Icons.balance_rounded),
            label: const Text("Can't decide"),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Judge the drawings only: their stars and artists don't show here. You never get a drawing of your own.",
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: controller.theme.isDark ? Colors.white70 : Colors.black54),
          textAlign: TextAlign.center,
        ),
      ],
    ];
  }
}

/// Today's votes: the pack and its stars, and the cap.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.week});

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stadium_rounded, color: AppPalette.rarityLegend),
                const SizedBox(width: 8),
                Expanded(child: Text("Week $week's challengers", style: textTheme.titleMedium)),
                Text('${status.challengers} in the Arena', style: textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: status.pack == 0 ? 1 : (status.votesToday / status.pack).clamp(0.0, 1.0),
                minHeight: 8,
                color: AppPalette.star,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              packDone
                  ? 'Today\'s ${status.packStars} ★ earned. ${status.canVote ? 'Keep voting if you like: '
                              '${status.cap - status.votesToday} more today.' : 'No more votes today.'}'
                  : '${status.votesToday} of ${status.pack} votes for today\'s ${status.packStars} ★',
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// One side of the matchup: the drawing big, who it portrays and its title.
class _Contender extends StatelessWidget {
  const _Contender({
    super.key,
    required this.card,
    required this.lean,
    required this.picked,
    required this.draw,
    required this.onTap,
    required this.hint,
  });

  final CharacterCard card;

  /// How far a swipe leans toward it, 0 to 1.
  final double lean;

  /// Whether it was picked, while the vote animates; null before.
  final bool? picked;
  final bool draw;
  final VoidCallback? onTap;

  /// How to pick it with the keyboard or a swipe.
  final String hint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final highlight = picked == true || lean > 0;
    final accent = draw ? colors.outline : AppPalette.rarityLegend;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: picked == false && !draw ? 0.35 : 1,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 200),
        scale: picked == true ? 1.05 : 1 + 0.04 * lean,
        child: Semantics(
          button: true,
          label: 'The better one: ${card.subject}, ${card.title}',
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: highlight || draw ? accent : colors.outlineVariant,
                width: highlight || draw ? 3 : 1,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: cardAspectRatio,
                      child: CardboardCard(child: SketchView(card.sketch)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      card.subject,
                      style: textTheme.titleMedium,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      card.title,
                      style: textTheme.bodySmall,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showsPagerArrows(context)) ...[
                      const SizedBox(height: 4),
                      Text(
                        hint,
                        style: textTheme.labelSmall?.copyWith(color: colors.outline),
                        textAlign: TextAlign.center,
                      ),
                    ],
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

/// A message instead of a matchup.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppPalette.rarityLegend),
            const SizedBox(height: 12),
            Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, style: textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
