import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../logic/duel.dart';
import '../logic/game_controller.dart';
import '../logic/models.dart';
import '../logic/upgrades.dart';
import '../widgets/card_art.dart';
import '../widgets/themed_background.dart';

/// Pick a fighter from your collection and battle one of today's challengers.
class DuelScreen extends StatefulWidget {
  const DuelScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> {
  late OwnedCard _fighter = widget.controller.collection.first;
  late CharacterCard _opponent = widget.controller.todaysChallengers.first;
  DuelResult? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duel')),
      body: ThemedBackground(
        theme: widget.controller.theme,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: Tween(begin: 1.1, end: 1.0).animate(animation), child: child),
          ),
          child: _result == null
              ? _buildSelection(context)
              : _DuelArena(
                  key: ValueKey(_result),
                  controller: widget.controller,
                  fighter: _fighter,
                  opponent: _opponent,
                  result: _result!,
                  onRematch: () => setState(() => _result = null),
                ),
        ),
      ),
    );
  }

  Widget _buildSelection(BuildContext context) {
    final controller = widget.controller;
    final fighterStats = FighterStats.of(_fighter.card.rarity, upgrades: _fighter.unlocked.length);
    final opponentStats = FighterStats.of(_opponent.rarity);
    return ListView(
      key: const ValueKey('selection'),
      padding: const EdgeInsets.all(16),
      children: [
        _section(context, 'Your fighter · ATK ${fighterStats.attack} · HP ${fighterStats.maxHp}'),
        _picker<OwnedCard>(
          items: controller.collection,
          selected: _fighter,
          cardOf: (o) => o.card,
          effectsOf: (o) => o.unlocked,
          elementOf: (o) => o.element,
          onSelected: (o) => setState(() => _fighter = o),
        ),
        const SizedBox(height: 16),
        _section(context, "Today's challenger · ATK ${opponentStats.attack} · HP ${opponentStats.maxHp}"),
        _picker<CharacterCard>(
          items: controller.todaysChallengers,
          selected: _opponent,
          cardOf: (c) => c,
          effectsOf: (_) => const [],
          elementOf: (_) => null,
          onSelected: (c) => setState(() => _opponent = c),
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20)),
            onPressed: () => setState(() => _result = controller.duel(_fighter, _opponent)),
            icon: const Icon(Icons.sports_martial_arts_rounded),
            label: const Text('Fight!'),
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }

  Widget _picker<T>({
    required List<T> items,
    required T selected,
    required CharacterCard Function(T) cardOf,
    required List<UpgradeEffect> Function(T) effectsOf,
    required ElementKind? Function(T) elementOf,
    required ValueChanged<T> onSelected,
  }) {
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final card = cardOf(item);
          final isSelected = item == selected;
          return GestureDetector(
            onTap: () => onSelected(item),
            child: AnimatedScale(
              scale: isSelected ? 1.0 : 0.85,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: isSelected ? 1 : 0.7,
                duration: const Duration(milliseconds: 250),
                child: SizedBox(
                  width: 110,
                  child: Column(
                    children: [
                      Standee(card: card, width: 100, effects: effectsOf(item), element: elementOf(item)),
                      const SizedBox(height: 4),
                      Nameplate(name: card.subject, title: card.title, rarity: card.rarity, compact: true),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DuelArena extends StatefulWidget {
  const _DuelArena({
    super.key,
    required this.controller,
    required this.fighter,
    required this.opponent,
    required this.result,
    required this.onRematch,
  });

  final GameController controller;
  final OwnedCard fighter;
  final CharacterCard opponent;
  final DuelResult result;
  final VoidCallback onRematch;

  @override
  State<_DuelArena> createState() => _DuelArenaState();
}

class _DuelArenaState extends State<_DuelArena> with TickerProviderStateMixin {
  late final _lunge = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  late final _impact = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final _idle = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  late final FighterStats _leftStats = FighterStats.of(
    widget.fighter.card.rarity,
    upgrades: widget.fighter.unlocked.length,
  );
  late final FighterStats _rightStats = FighterStats.of(widget.opponent.rarity);
  Timer? _timer;
  int _shown = 0;
  bool _finished = false;
  bool _rewarded = false;

  DuelHit? get _lastHit => _shown == 0 ? null : widget.result.hits[_shown - 1];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _nextHit());
  }

  void _nextHit() {
    if (_shown >= widget.result.hits.length) {
      _timer?.cancel();
      setState(() {
        _finished = true;
        _rewarded = widget.controller.recordDuel(widget.result);
      });
      return;
    }
    setState(() => _shown++);
    _lunge.forward(from: 0).then((_) {
      if (mounted) _lunge.reverse();
    });
    _impact.forward(from: 0);
  }

  void _skip() {
    if (_finished) return;
    _timer?.cancel();
    setState(() {
      _shown = widget.result.hits.length;
      _finished = true;
      _rewarded = widget.controller.recordDuel(widget.result);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lunge.dispose();
    _impact.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hit = _lastHit;
    final leftHp = hit?.leftHp ?? _leftStats.maxHp;
    final rightHp = hit?.rightHp ?? _rightStats.maxHp;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedBuilder(
        animation: Listenable.merge([_lunge, _impact, _idle]),
        builder: (context, _) {
          final critShake = hit != null && hit.critical ? sin(_impact.value * pi * 12) * 10 * (1 - _impact.value) : 0.0;
          return Transform.translate(
            offset: Offset(critShake, 0),
            child: Stack(
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _HpBar(hp: leftHp, maxHp: _leftStats.maxHp, label: widget.fighter.card.subject),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                            ),
                            Expanded(
                              child: _HpBar(
                                hp: rightHp,
                                maxHp: _rightStats.maxHp,
                                label: widget.opponent.subject,
                                alignEnd: true,
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final width = min(180.0, constraints.maxWidth * 0.36);
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _fighterWidget(isLeft: true, width: width),
                                  _fighterWidget(isLeft: false, width: width),
                                ],
                              );
                            },
                          ),
                        ),
                        if (!_finished)
                          Text('Tap to skip', style: TextStyle(color: Colors.black.withValues(alpha: 0.5))),
                      ],
                    ),
                  ),
                ),
                if (_finished) _resultOverlay(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _fighterWidget({required bool isLeft, required double width}) {
    final hit = _lastHit;
    final attacking = hit != null && hit.byLeft == isLeft;
    final defending = hit != null && hit.byLeft != isLeft;
    final direction = isLeft ? 1.0 : -1.0;
    final lunge = attacking ? Curves.easeOut.transform(_lunge.value) * 40 * direction : 0.0;
    final recoil = defending ? sin(_impact.value * pi) * -14 * direction : 0.0;
    final bob = sin(_idle.value * 2 * pi + (isLeft ? 0 : pi)) * 4;
    final lost = _finished && (widget.result.leftWins != isLeft);
    final card = isLeft ? widget.fighter.card : widget.opponent;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        AnimatedRotation(
          turns: lost ? direction * -0.06 : 0,
          duration: const Duration(milliseconds: 600),
          child: AnimatedOpacity(
            opacity: lost ? 0.5 : 1,
            duration: const Duration(milliseconds: 600),
            child: Transform.translate(
              offset: Offset(lunge + recoil, bob),
              child: Standee(
                card: card,
                width: width,
                effects: isLeft ? widget.fighter.unlocked : const [],
                element: isLeft ? widget.fighter.element : null,
              ),
            ),
          ),
        ),
        if (defending)
          Positioned(
            top: -20 - _impact.value * 40,
            child: Opacity(
              opacity: 1 - _impact.value,
              child: Text(
                '-${hit.damage}${hit.critical ? '!' : ''}',
                style: TextStyle(
                  fontSize: hit.critical ? 40 : 30,
                  fontWeight: FontWeight.w900,
                  color: hit.critical ? AppPalette.rarityLegend : AppPalette.hurry,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _resultOverlay(BuildContext context) {
    final won = widget.result.leftWins;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (context, value, child) => Transform.scale(scale: value, child: child),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      won ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded,
                      size: 56,
                      color: won ? AppPalette.rarityLegend : AppPalette.defeat,
                    ),
                    Text(
                      won ? 'Victory!' : 'Defeat',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: won ? AppPalette.victory : AppPalette.defeat,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (_rewarded) const Text('First win of the day: +1 pull!'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(onPressed: widget.onRematch, child: const Text('Fight again')),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
                      ],
                    ),
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

class _HpBar extends StatelessWidget {
  const _HpBar({required this.hp, required this.maxHp, required this.label, this.alignEnd = false});

  final int hp;
  final int maxHp;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final fraction = hp / maxHp;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text('$label  $hp/$maxHp', style: Theme.of(context).textTheme.labelLarge, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            TweenAnimationBuilder<double>(
              tween: Tween(end: fraction),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  color: Color.lerp(AppPalette.hpLow, AppPalette.hpHigh, value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
