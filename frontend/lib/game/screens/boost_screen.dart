import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/daily_loop.dart';
import '../game_session.dart';
import '../widgets/animated_fight.dart';
import '../widgets/game_action.dart';

/// Step 4: browse yesterday's challengers and the teams sent against them,
/// and boost one of them. Every boost adds a star more than the one before.
class BoostScreen extends StatefulWidget {
  const BoostScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<BoostScreen> createState() => _BoostScreenState();
}

class _BoostScreenState extends State<BoostScreen> {
  late final List<BoostTarget> _targets = widget.controller.boostTargets;
  late final _pages = PageController(initialPage: _firstPage());
  late int _page = _firstPage();

  /// The challenger you boosted, if you did.
  int _firstPage() {
    final index = _targets.indexWhere((t) => t.challenger.id == widget.controller.boostedChallengerId);
    return index < 0 ? 0 : index;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _boost(BoostTarget target) async {
    if (!await runGameAction(context, () => widget.controller.boost(target.challenger))) return;
    if (!mounted) return;
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Boost a challenger ${_page + 1}/${_targets.length}')),
      body: PageView.builder(
        controller: _pages,
        itemCount: _targets.length,
        onPageChanged: (page) => setState(() => _page = page),
        itemBuilder: (context, index) => _BoostPage(
          key: ValueKey(_targets[index].challenger.id),
          target: _targets[index],
          boosted: widget.controller.boostedChallengerId,
          onBoost: () => _boost(_targets[index]),
        ),
      ),
    );
  }
}

class _BoostPage extends StatefulWidget {
  const _BoostPage({super.key, required this.target, required this.boosted, required this.onBoost});

  final BoostTarget target;

  /// The id of the challenger you boosted today, if any.
  final String? boosted;
  final VoidCallback onBoost;

  @override
  State<_BoostPage> createState() => _BoostPageState();
}

class _BoostPageState extends State<_BoostPage> {
  int _matchup = 0;

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final challenger = target.challenger;
    final fight = target.matchups[_matchup];
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: ListTile(
            leading: const Icon(Icons.shield_rounded, color: AppPalette.rarityHero),
            title: Text('${challenger.subject} · ${challenger.title}'),
            subtitle: Text(
              'Drawn by ${challenger.artist} · ${'★' * Stars.challengerBase} before boosts · '
              '${target.matchups.length} team${target.matchups.length == 1 ? '' : 's'} against it',
            ),
          ),
        ),
        if (target.matchups.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (i, matchup) in target.matchups.indexed)
                  ChoiceChip(
                    label: Text(matchup.owner.name),
                    selected: i == _matchup,
                    onSelected: (_) => setState(() => _matchup = i),
                  ),
              ],
            ),
          ),
        Expanded(
          // An undecided skirmish loops while you make up your mind.
          child: AnimatedFight(
            key: ValueKey(fight.id),
            fight: fight,
            beats: FightScript.skirmish(fighterCount: fight.fighters.length, random: Random(fight.id.hashCode)),
            loop: true,
          ),
        ),
        Text(
          "${fight.owner.name}'s ${fight.fighters.length} fighter${fight.fighters.length == 1 ? '' : 's'}: "
          '${fight.fighterStars} ★',
          style: textTheme.titleMedium,
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: switch (widget.boosted) {
                null => FilledButton.icon(
                  key: const ValueKey('boost'),
                  style: FilledButton.styleFrom(backgroundColor: AppPalette.rarityHero),
                  onPressed: widget.onBoost,
                  icon: const Icon(Icons.keyboard_double_arrow_up_rounded),
                  label: Text('Boost ${challenger.subject}'),
                ),
                final boosted when boosted == challenger.id => Text(
                  key: const ValueKey('boosted'),
                  'You boosted ${challenger.subject} today',
                  style: textTheme.titleMedium,
                ),
                _ => Text(
                  key: const ValueKey('other'),
                  'You boosted another challenger today',
                  style: textTheme.bodyMedium,
                ),
              },
            ),
          ),
        ),
      ],
    );
  }
}
