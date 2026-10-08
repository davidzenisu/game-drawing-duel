import 'dart:math';

import 'package:flutter/material.dart';

import '../logic/daily_loop.dart';
import '../logic/models.dart';
import '../logic/themes.dart';
import 'card_art.dart';
import 'sketch_canvas.dart';
import 'themed_background.dart';

/// Wraps a standee, e.g. to animate it or add an HP bar.
typedef StandeeWrapper = Widget Function(BuildContext context, Widget standee);

/// The fight layout from `docs/images`: the challenger stands large at the
/// top next to its nameplate, up to four smaller fighters line up below.
class FightStage extends StatelessWidget {
  const FightStage({
    super.key,
    required this.theme,
    required this.challenger,
    required this.fighters,
    this.showEmptySlots = false,
    this.onSlotTap,
    this.wrapChallenger,
    this.wrapFighter,
  });

  final DailyTheme theme;
  final CharacterCard challenger;
  final List<FighterEntry> fighters;

  /// Fills the row up to four with empty, tappable slots.
  final bool showEmptySlots;
  final ValueChanged<int>? onSlotTap;
  final StandeeWrapper? wrapChallenger;
  final Widget Function(BuildContext context, int index, Widget standee)? wrapFighter;

  /// Height of a standee relative to its width (card plus base).
  static const _standeeHeight = 1 / cardAspectRatio + 0.62 * 0.32;

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      theme: theme,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final topHeight = height * 0.58;
          final bottomHeight = height - topHeight;
          final challengerWidth = min(width * 0.42, (topHeight - 32) / _standeeHeight);
          final slots = showEmptySlots ? FightSetup.maxFighters : fighters.length;
          final slotSpace = (width - 16) / FightSetup.maxFighters;
          const plateHeight = 76.0;
          final fighterWidth = min(slotSpace * 0.78, (bottomHeight - plateHeight - 24) / _standeeHeight);

          final challengerStandee = Standee(card: challenger, width: challengerWidth);
          return Column(
            children: [
              SizedBox(
                height: topHeight,
                child: Row(
                  children: [
                    Expanded(
                      flex: 12,
                      child: Center(child: wrapChallenger?.call(context, challengerStandee) ?? challengerStandee),
                    ),
                    Expanded(
                      flex: 8,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Align(
                          alignment: const Alignment(0, -0.35),
                          child: SizedBox(
                            width: double.infinity,
                            child: Nameplate(
                              name: challenger.subject,
                              title: challenger.title,
                              rarity: challenger.rarity,
                              nameFirst: true,
                              large: width > 360,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: bottomHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < slots; i++)
                        SizedBox(
                          width: slotSpace,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: i < fighters.length
                                ? _fighter(context, i, fighterWidth)
                                : _EmptySlot(
                                    width: fighterWidth,
                                    onTap: onSlotTap == null ? null : () => onSlotTap!(i),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fighter(BuildContext context, int index, double width) {
    final fighter = fighters[index];
    final standee = Standee(card: fighter.card, width: width, effects: fighter.effects, element: fighter.element);
    final wrapped = wrapFighter?.call(context, index, standee) ?? standee;
    return GestureDetector(
      onTap: onSlotTap == null ? null : () => onSlotTap!(index),
      child: Column(
        children: [
          wrapped,
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64, minWidth: double.infinity),
            child: Nameplate(name: fighter.card.subject, title: fighter.card.title, compact: true),
          ),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.width, this.onTap});

  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: width,
            height: width / cardAspectRatio,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
          ),
        ),
        StandeeBase(width: width * 0.62),
        const SizedBox(height: 6),
        Text(
          'Add fighter',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            shadows: const [Shadow(blurRadius: 3, color: Colors.black54)],
          ),
        ),
      ],
    );
  }
}
