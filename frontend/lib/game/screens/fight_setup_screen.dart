import 'package:flutter/material.dart';

import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../rules/upgrades.dart';
import '../widgets/card_art.dart';
import '../widgets/fight_stage.dart';
import '../widgets/game_action.dart';
import 'fight_replay_screen.dart';

/// Step 4: pick up to four fighters against a challenger the others boosted
/// yesterday. Its boosts stay secret until you lock in, then the stars
/// decide and the fight plays out. After a fight, a character rests a few
/// days, by its rarity.
class FightSetupScreen extends StatefulWidget {
  const FightSetupScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<FightSetupScreen> createState() => _FightSetupScreenState();
}

class _FightSetupScreenState extends State<FightSetupScreen> {
  final List<OwnedCard> _picked = [];

  /// This week's win rates, once loaded: the star changes your fighters
  /// bring against the challenger's player.
  WeekWinRates? _rates;

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  Future<void> _loadRates() async {
    try {
      final rates = await widget.controller.winRates();
      if (mounted) setState(() => _rates = rates);
    } on Object {
      // Without them, the picker just shows no star changes.
    }
  }

  /// The win rate star change [card] brings against today's challenger:
  /// its extra stars, minus the challenger's against it.
  int _starChange(CharacterCard card) {
    final rates = _rates;
    if (rates == null) return 0;
    final against = widget.controller.fightChallenger!.subject;
    return rates.extraStars(card.subject, against) - rates.extraStars(against, card.subject);
  }

  /// The extra stars [fighters] and the challenger get from the win rates.
  (int yours, int challenger) _extraStarsOf(List<FighterEntry> fighters) {
    final rates = _rates;
    if (rates == null) return (0, 0);
    final against = widget.controller.fightChallenger!.subject;
    return (
      fighters.fold(0, (sum, f) => sum + rates.extraStars(f.card.subject, against)),
      fighters.fold(0, (sum, f) => sum + rates.extraStars(against, f.card.subject)),
    );
  }

  int _yourExtraStars(List<FighterEntry> fighters) => _extraStarsOf(fighters).$1;

  /// What the picked fighters' win rates change, if anything.
  String? _winRateSummary(List<FighterEntry> fighters) {
    final (yours, theirs) = _extraStarsOf(fighters);
    if (yours == 0 && theirs == 0) return null;
    return 'Win rates: ${[if (yours > 0) 'your fighters +$yours ★', if (theirs > 0) 'the challenger +$theirs ★'].join(' · ')}';
  }

  Future<void> _openRoster() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void toggle(OwnedCard owned) {
            setState(() {
              if (_picked.contains(owned)) {
                _picked.remove(owned);
              } else if (_picked.length < FightSetup.maxFighters) {
                _picked.add(owned);
              }
            });
            setSheetState(() {});
          }

          // The resting characters come last, the ones back soonest first.
          final controller = widget.controller;
          final roster = [
            ...controller.availableFighters,
            ...controller.collection.where(controller.isResting).toList()
              ..sort((a, b) => controller.restDaysLeft(a).compareTo(controller.restDaysLeft(b))),
          ];
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: Column(
              children: [
                Text(
                  'Your roster · ${_picked.length}/${FightSetup.maxFighters} picked',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 130,
                      mainAxisExtent: 210,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: roster.length,
                    itemBuilder: (context, index) {
                      final owned = roster[index];
                      final selected = _picked.contains(owned);
                      final full = _picked.length >= FightSetup.maxFighters;
                      final restDays = controller.restDaysLeft(owned);
                      final resting = restDays > 0;
                      final pickable = !resting && (selected || !full);
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: pickable ? () => toggle(owned) : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: Opacity(
                            opacity: pickable ? 1 : 0.4,
                            child: Column(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Standee(card: owned.card, width: 90, effects: owned.shown, element: owned.element),
                                    if (resting) Positioned(top: 0, right: 0, child: RestBadge(days: restDays)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    StarRow(rarity: owned.card.rarity, size: 12),
                                    if (_starChange(owned.card) case final change when change != 0) ...[
                                      const SizedBox(width: 4),
                                      StarChangeBadge(change: change),
                                    ],
                                  ],
                                ),
                                Text(owned.card.subject, overflow: TextOverflow.ellipsis),
                                Text(
                                  resting ? 'Resting, ${backIn(restDays)}' : owned.card.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final challenger = controller.fightChallenger!;
    final locked = controller.yourFight;
    final List<FighterEntry> fighters = locked?.fighters ?? [for (final o in _picked) FighterEntry.fromOwned(o)];
    return Scaffold(
      appBar: AppBar(title: Text(locked == null ? 'Pick your fighters' : 'Fighters locked in')),
      body: Column(
        children: [
          Expanded(
            child: FightStage(
              theme: challenger.scenery,
              challenger: challenger,
              fighters: fighters,
              showEmptySlots: locked == null,
              onSlotTap: locked == null ? (_) => _openRoster() : null,
              starChanges: [for (final f in fighters) _starChange(f.card)],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: locked != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${locked.fightersWin ? 'You won' : 'You lost'}: ${locked.fighterTotal} ★ against '
                          '${locked.challengerTotal} ★'
                          '${_extraStars(locked)}.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                          ).push(MaterialPageRoute<void>(builder: (_) => FightReplayScreen(fight: locked))),
                          icon: const Icon(Icons.play_circle_fill_rounded),
                          label: const Text('Watch the fight'),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'The challenger has ${Stars.challengerBase} ★ plus the boosts it got yesterday, secret '
                          'until you lock in. Bring more: ties go to the challenger.',
                          textAlign: TextAlign.center,
                        ),
                        if (_winRateSummary(fighters) case final summary?) ...[
                          const SizedBox(height: 4),
                          Text(summary, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openRoster,
                                icon: const Icon(Icons.groups_rounded),
                                label: const Text('Roster'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _picked.isEmpty
                                    ? null
                                    : () async {
                                        final locked = await runGameAction(
                                          context,
                                          () => controller.submitFighters(_picked),
                                        );
                                        final fight = controller.yourFight;
                                        if (!locked || fight == null || !context.mounted) return;
                                        // The stars decide right away: watch the fight.
                                        await Navigator.of(context).pushReplacement(
                                          MaterialPageRoute<bool>(
                                            builder: (_) => FightReplayScreen(
                                              fight: fight,
                                              rewardPulls: controller.pullsForWin(fight),
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.lock_rounded),
                                label: Text(
                                  'Lock in ${_picked.length}/${FightSetup.maxFighters} · '
                                  '${Stars.ofTeam(_picked.map((o) => o.card.rarity)) + _yourExtraStars(fighters)} ★',
                                ),
                              ),
                            ),
                          ],
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

/// The win rate extra stars in [fight]'s stars, if any.
String _extraStars(FightSetup fight) {
  final parts = [
    if (fight.fighterExtraStars > 0) 'yours +${fight.fighterExtraStars}',
    if (fight.challengerExtraStars > 0) "the challenger's +${fight.challengerExtraStars}",
  ];
  return parts.isEmpty ? '' : ' (win rate extra stars: ${parts.join(', ')})';
}

/// The days a character still rests after a fight, on its card in the
/// roster: a moon and the number of days.
class RestBadge extends StatelessWidget {
  const RestBadge({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Resting, ${backIn(days)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: colors.inverseSurface, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bedtime_rounded, size: 12, color: colors.onInverseSurface),
            const SizedBox(width: 2),
            Text(
              '${days}d',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.onInverseSurface, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
