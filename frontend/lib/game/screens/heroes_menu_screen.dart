import 'package:flutter/material.dart';

import '../game_session.dart';
import '../tutorials.dart';
import '../unavailable.dart';
import '../widgets/game_action.dart';
import '../widgets/hub_tile.dart';
import '../widgets/notification_board.dart';
import '../widgets/ticket_chip.dart';
import '../widgets/tutorial_dialog.dart';
import 'challengers_screen.dart';
import 'collection_screen.dart';
import 'fight_history_screen.dart';
import 'gacha_screen.dart';
import 'ranking_screen.dart';
import 'rewards_screen.dart';
import 'win_rates_screen.dart';

/// Everything around your heroes, off the daily hub: summoning, your
/// heroes, the challengers, rewards, win rates, replays of past fights, the
/// week ranking and hurries. What doesn't apply right now is greyed out.
class HeroesMenuScreen extends StatelessWidget {
  const HeroesMenuScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    Future<void> open(Widget screen, [Tutorial? intro]) async {
      if (intro != null) await showTutorialOnce(context, controller, intro);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Heroes'),
            actions: [
              NotificationBoardButton(session: c),
              TicketChip(
                tickets: c.tickets,
                stars: c.stars,
                onBuyPull: () => runGameAction(context, c.buyPullWithStars),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SummonTile(
                        pulls: c.tickets,
                        onTap: () => open(GachaScreen(controller: c), Tutorial.gacha),
                      ),
                      const SizedBox(height: 16),
                      HubGrid(
                        tiles: [
                          HubTile(
                            icon: Icons.collections_rounded,
                            title: 'Hero List',
                            badge: c.upgradesAvailable,
                            onTap: () => open(CollectionScreen(controller: c), Tutorial.upgrades),
                          ),
                          HubTile(
                            icon: Icons.shield_rounded,
                            title: 'Challengers',
                            badge: c.challengersToCollect,
                            onTap: () => open(ChallengersScreen(controller: c)),
                          ),
                          HubTile(
                            icon: Icons.military_tech_rounded,
                            title: 'Rewards',
                            badge: c.achievementsToCollect,
                            onTap: () => open(RewardsScreen(controller: c)),
                          ),
                          HubTile(
                            icon: Icons.percent_rounded,
                            title: 'Win rates',
                            unavailable: Unavailable.winRates(c),
                            // Once the first week is over, so they don't give
                            // away everyone's basic drawing; speed mode has none.
                            onTap: c.weeklyHero == null || c.server.isSpeed
                                ? null
                                : () => open(WinRatesScreen(controller: c)),
                          ),
                          HubTile(
                            icon: Icons.play_circle_fill_rounded,
                            title: 'Fight replay',
                            unavailable: Unavailable.fightReplay(c),
                            // Every fight of the days before today.
                            onTap: Unavailable.fightReplay(c) == null
                                ? () => open(FightHistoryScreen(controller: c))
                                : null,
                          ),
                          HubTile(
                            icon: Icons.emoji_events_rounded,
                            title: 'Week ranking',
                            unavailable: Unavailable.weekRanking(c),
                            // Once a week is over; speed mode has its own finale.
                            onTap: c.weeklyHero == null || c.server.isSpeed
                                ? null
                                : () => open(RankingScreen(controller: c), Tutorial.finale),
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
      },
    );
  }
}
