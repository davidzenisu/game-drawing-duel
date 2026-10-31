import 'package:flutter/material.dart';

import '../rules/daily_loop.dart';
import '../game_session.dart';
import '../rules/upgrades.dart';
import '../widgets/card_art.dart';
import '../widgets/fight_stage.dart';
import '../widgets/game_action.dart';
import 'fight_replay_screen.dart';

/// Step 4: pick up to four fighters against a challenger the others boosted
/// yesterday. Its boosts stay secret until you lock in, then the stars
/// decide and the fight plays out. Every character fights once a week.
class FightSetupScreen extends StatefulWidget {
  const FightSetupScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<FightSetupScreen> createState() => _FightSetupScreenState();
}

class _FightSetupScreenState extends State<FightSetupScreen> {
  final List<OwnedCard> _picked = [];

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

          // The characters that already fought this week come last.
          final controller = widget.controller;
          final roster = [...controller.availableFighters, ...controller.collection.where(controller.isResting)];
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
                      final resting = controller.isResting(owned);
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
                                Standee(card: owned.card, width: 90, effects: owned.shown, element: owned.element),
                                const SizedBox(height: 4),
                                StarRow(rarity: owned.card.rarity, size: 12),
                                Text(owned.card.subject, overflow: TextOverflow.ellipsis),
                                Text(
                                  resting ? 'Resting until Monday' : owned.card.title,
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
                          '${locked.fightersWin ? 'You won' : 'You lost'}: ${locked.fighterStars} ★ against '
                          '${locked.challengerStars} ★.',
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
                                  '${Stars.ofTeam(_picked.map((o) => o.card.rarity))} ★',
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
