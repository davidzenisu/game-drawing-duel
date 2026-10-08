import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../logic/daily_loop.dart';
import '../logic/game_controller.dart';
import '../widgets/animated_fight.dart';

/// Step 4: vote who would win the fights the others set up yesterday.
class VoteScreen extends StatefulWidget {
  const VoteScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  late final List<FightSetup> _fights = widget.controller.fightsToVote;
  late final _pages = PageController(initialPage: _firstOpen());
  late int _page = _firstOpen();

  int _firstOpen() {
    final index = _fights.indexWhere((f) => !widget.controller.hasVoted(f));
    return index < 0 ? 0 : index;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _vote(FightSetup fight, {required bool fightersWin}) async {
    widget.controller.vote(fight, fightersWin: fightersWin);
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    if (_page < _fights.length - 1) {
      _pages.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    } else if (widget.controller.votesLeft == 0) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Who would win? ${_page + 1}/${_fights.length}')),
      body: PageView.builder(
        controller: _pages,
        itemCount: _fights.length,
        onPageChanged: (page) => setState(() => _page = page),
        itemBuilder: (context, index) => _buildPage(context, _fights[index]),
      ),
    );
  }

  Widget _buildPage(BuildContext context, FightSetup fight) {
    final voted = widget.controller.hasVoted(fight);
    final choice = fight.votes[widget.controller.you.id];
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: ListTile(
            leading: CircleAvatar(child: Text(fight.owner.name.characters.first)),
            title: Text("${fight.owner.name}'s fighters"),
            subtitle: Text('vs. ${fight.challenger.subject}, drawn by ${fight.challenger.artist}'),
          ),
        ),
        Expanded(
          // An undecided skirmish loops while you make up your mind.
          child: AnimatedFight(
            fight: fight,
            beats: FightScript.skirmish(fighterCount: fight.fighters.length, random: Random(fight.id.hashCode)),
            loop: true,
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: voted
                  ? Text(
                      key: const ValueKey('voted'),
                      choice! ? 'You voted for the fighters' : 'You voted for the challenger',
                      style: Theme.of(context).textTheme.titleMedium,
                    )
                  : Row(
                      key: const ValueKey('vote'),
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppPalette.rarityHero),
                            onPressed: () => _vote(fight, fightersWin: false),
                            icon: const Icon(Icons.shield_rounded),
                            label: const Text('Challenger wins'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppPalette.victory),
                            onPressed: () => _vote(fight, fightersWin: true),
                            icon: const Icon(Icons.groups_rounded),
                            label: const Text('Fighters win'),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
