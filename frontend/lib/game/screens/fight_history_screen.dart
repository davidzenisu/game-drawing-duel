import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import 'fight_replay_screen.dart';

/// E.g. "Saturday, 10 October 2026".
String fightDate(DateTime date) {
  const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
}

/// The days before today with fights, newest first, each opening that
/// day's challengers to replay their fights.
class FightHistoryScreen extends StatefulWidget {
  const FightHistoryScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<FightHistoryScreen> createState() => _FightHistoryScreenState();
}

class _FightHistoryScreenState extends State<FightHistoryScreen> {
  List<FightDay>? _days;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // After the first frame, so errors can show in the scaffold.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final days = await runGameQuery(context, widget.controller.fightDays);
    if (!mounted) return;
    setState(() {
      _days = days;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _days ?? const [];
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Fight replay')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : days.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No fights to replay yet: they show here the day after.', textAlign: TextAlign.center),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final day = days[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      foregroundColor: colors.onPrimaryContainer,
                      child: Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    title: Text('Day ${day.day}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(fightDate(day.date)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DayFightsScreen(controller: widget.controller, day: day),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Every challenger fought on a past day, the one you drew and the one you
/// fought first and highlighted; tap one to replay its fight.
class DayFightsScreen extends StatefulWidget {
  const DayFightsScreen({super.key, required this.controller, required this.day});

  final GameSession controller;
  final FightDay day;

  @override
  State<DayFightsScreen> createState() => _DayFightsScreenState();
}

class _DayFightsScreenState extends State<DayFightsScreen> {
  List<FightSetup>? _fights;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final fights = await runGameQuery(context, () => widget.controller.fightsOn(widget.day.day));
    if (!mounted) return;
    setState(() {
      _fights = fights;
      _loading = false;
    });
  }

  bool _fought(FightSetup fight) => fight.owner.isYou;

  bool _drew(FightSetup fight) => fight.challenger.artist == widget.controller.you.name;

  @override
  Widget build(BuildContext context) {
    // Yours first: the one you fought, then the one you drew.
    int rank(FightSetup f) => _fought(f) ? 0 : (_drew(f) ? 1 : 2);
    final fights = [...?_fights]..sort((a, b) => rank(a).compareTo(rank(b)));
    return Scaffold(
      appBar: AppBar(title: Text('Day ${widget.day.day}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      fights.isEmpty
                          ? 'No fights on this day.'
                          : '${fightDate(widget.day.date)}. Tap a challenger to replay its fight.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      // Room for the mark, titles on two lines and the result.
                      mainAxisExtent: 380,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: fights.length,
                    itemBuilder: (context, i) => _FightTile(
                      fight: fights[i],
                      fought: _fought(fights[i]),
                      drew: _drew(fights[i]),
                      onTap: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => FightReplayScreen(fight: fights[i]))),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FightTile extends StatelessWidget {
  const _FightTile({required this.fight, required this.fought, required this.drew, required this.onTap});

  final FightSetup fight;
  final bool fought;
  final bool drew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final card = fight.challenger;
    final highlight = fought ? colors.primary : (drew ? AppPalette.rarityLegend : null);
    final owner = fought ? 'your' : "${fight.owner.name}'s";
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: highlight == null
          ? colors.surfaceContainerHigh
          : Color.alphaBlend(highlight.withValues(alpha: 0.14), colors.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight == null ? BorderSide(color: colors.outlineVariant) : BorderSide(color: highlight, width: 3),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              SizedBox(
                height: 24,
                child: highlight == null
                    ? null
                    : FittedBox(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: highlight, borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  fought ? Icons.shield_rounded : Icons.brush_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  fought ? 'You fought it' : 'You drew it',
                                  style: text.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              Standee(card: card, width: 100),
              const SizedBox(height: 6),
              Nameplate(name: card.subject, title: card.title, rarity: card.rarity, compact: true),
              const SizedBox(height: 4),
              Text(
                'by ${card.artist}',
                style: text.labelSmall,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    fight.fightersWin ? Icons.close_rounded : Icons.emoji_events_rounded,
                    size: 16,
                    color: fight.fightersWin ? colors.error : AppPalette.victory,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      fight.fightersWin ? 'Beaten by $owner team' : 'Beat $owner team',
                      style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text('${fight.fighterTotal} ★ vs ${fight.challengerTotal} ★', style: text.labelSmall),
              const Icon(Icons.play_circle_fill_rounded, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
