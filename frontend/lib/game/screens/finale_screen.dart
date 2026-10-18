import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';

/// Step 5, on the last day of a week: vote on pairs of the week's
/// challengers that won a fight. Swipe left for the left one and right for
/// the right one, or tap the one you pick; each vote adds a star to it.
class FinaleScreen extends StatefulWidget {
  const FinaleScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<FinaleScreen> createState() => _FinaleScreenState();
}

class _FinaleScreenState extends State<FinaleScreen> {
  /// How far the pair was dragged sideways, to lean towards a pick.
  double _drag = 0;
  bool _voting = false;

  static const _swipeDistance = 80.0;
  static const _swipeVelocity = 400.0;

  Future<void> _vote(CharacterCard chosen, CharacterCard other) async {
    if (_voting) return;
    setState(() => _voting = true);
    await runGameAction(context, () => widget.controller.voteFinale(chosen, other));
    if (mounted) {
      setState(() {
        _voting = false;
        _drag = 0;
      });
    }
  }

  void _swiped((CharacterCard, CharacterCard) pair, double velocity) {
    final (left, right) = pair;
    if (_drag <= -_swipeDistance || velocity <= -_swipeVelocity) {
      _vote(left, right);
    } else if (_drag >= _swipeDistance || velocity >= _swipeVelocity) {
      _vote(right, left);
    } else {
      setState(() => _drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ballot = widget.controller.finale;
        return Scaffold(
          appBar: AppBar(
            title: Text(ballot == null || ballot.pairs == 0 ? 'Finale' : 'Finale · ${ballot.votes}/${ballot.pairs}'),
          ),
          body: switch (ballot) {
            null => const _Message(icon: Icons.event_rounded, text: 'The finale is on the last day of every week.'),
            FinaleBallot(pairs: 0) => _Message(
              icon: Icons.hourglass_empty_rounded,
              text: ballot.contenders == 0
                  ? 'No challenger won a fight this week, so there\'s no new hero.'
                  : 'Not enough challengers you didn\'t draw won a fight this week to vote on. '
                        'The one with the most stars joins the pool tomorrow.',
            ),
            FinaleBallot(pair: null) => _Message(
              icon: Icons.how_to_vote_rounded,
              text:
                  'You voted on all ${ballot.pairs} pairs. The challenger with the most stars '
                  'joins the gacha pool as a hero tomorrow.',
            ),
            FinaleBallot(pair: final pair?) => _ballot(ballot, pair),
          },
        );
      },
    );
  }

  Widget _ballot(FinaleBallot ballot, (CharacterCard, CharacterCard) pair) {
    final (left, right) = pair;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        children: [
          LinearProgressIndicator(value: ballot.votes / ballot.pairs),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Who is the best of the week? Swipe left or right, or tap your pick. '
              'Each vote adds a star; the one with the most joins the gacha pool tomorrow.',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: _voting ? null : (details) => setState(() => _drag += details.delta.dx),
              onHorizontalDragEnd: _voting ? null : (details) => _swiped(pair, details.primaryVelocity ?? 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: child),
                ),
                child: Transform.translate(
                  key: ValueKey('${left.id}|${right.id}'),
                  offset: Offset(_drag.clamp(-_swipeDistance, _swipeDistance) / 2, 0),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _Pick(
                            card: left,
                            leaning: _drag <= -_swipeDistance / 2,
                            onTap: _voting ? null : () => _vote(left, right),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('VS', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                        ),
                        Expanded(
                          child: _Pick(
                            card: right,
                            leaning: _drag >= _swipeDistance / 2,
                            onTap: _voting ? null : () => _vote(right, left),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _voting ? null : () => _vote(left, right),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: Text(left.subject, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _voting ? null : () => _vote(right, left),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(right.subject, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two challengers to pick from.
class _Pick extends StatelessWidget {
  const _Pick({required this.card, required this.leaning, required this.onTap});

  final CharacterCard card;

  /// Whether the swipe so far points at this one.
  final bool leaning;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnimatedScale(
      scale: leaning ? 1.06 : 1,
      duration: const Duration(milliseconds: 150),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: leaning ? AppPalette.rarityHero : Colors.transparent, width: 3),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Scales down to fit small screens.
                Flexible(
                  child: FittedBox(child: Standee(card: card, width: 180)),
                ),
                const SizedBox(height: 8),
                Nameplate(name: card.subject, title: card.title, compact: true, nameFirst: true),
                const SizedBox(height: 4),
                Text('Drawn by ${card.artist}', style: text.labelSmall, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(text, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
