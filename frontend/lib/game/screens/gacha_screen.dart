import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/gacha.dart';
import '../game_session.dart';
import '../rules/models.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/themed_background.dart';
import '../widgets/ticket_chip.dart';

class GachaScreen extends StatelessWidget {
  const GachaScreen({super.key, required this.controller});

  final GameSession controller;

  Future<void> _pull(BuildContext context, int count) async {
    final outcomes = await runGameQuery(context, () => controller.pull(count));
    if (outcomes == null || !context.mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => PullRevealScreen(outcomes: outcomes),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final gacha = controller.gachaStatus;
        final textTheme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Summon'),
            actions: [
              TicketChip(tickets: controller.tickets),
              const SizedBox(width: 12),
            ],
          ),
          body: ThemedBackground(
            theme: controller.theme,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        const Center(child: _FloatingCardBack(width: 160)),
                        const SizedBox(height: 32),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rates', style: textTheme.titleMedium),
                                const SizedBox(height: 8),
                                for (final MapEntry(key: rarity, value: rate) in GachaMachine.rates.entries)
                                  Row(
                                    children: [
                                      StarRow(rarity: rarity),
                                      const SizedBox(width: 8),
                                      Text(rarity.label),
                                      const Spacer(),
                                      Text('$rate%'),
                                    ],
                                  ),
                                const Divider(height: 24),
                                if (gacha.beginnerPullsLeft != null)
                                  Text('★★★ or better guaranteed within the next ${gacha.beginnerPullsLeft} pulls'),
                                Text('★★★★ guaranteed within ${gacha.pullsUntilLegend} pulls'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: controller.tickets >= 1 ? () => _pull(context, 1) : null,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Pull ×1'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: controller.tickets >= 10 ? () => _pull(context, 10) : null,
                                icon: const Icon(Icons.auto_awesome_rounded),
                                label: const Text('Pull ×10'),
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
          ),
        );
      },
    );
  }
}

/// The back of a character card, used before the reveal.
class CardBack extends StatelessWidget {
  const CardBack({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 4),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppPalette.nameplateTop, AppPalette.nameplateBottom],
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6)),
            ],
          ),
          child: Center(
            child: Icon(Icons.brush_rounded, color: Colors.white.withValues(alpha: 0.85), size: width * 0.4),
          ),
        ),
      ),
    );
  }
}

class _FloatingCardBack extends StatefulWidget {
  const _FloatingCardBack({required this.width});

  final double width;

  @override
  State<_FloatingCardBack> createState() => _FloatingCardBackState();
}

class _FloatingCardBackState extends State<_FloatingCardBack> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * pi;
        return Transform.translate(
          offset: Offset(0, sin(t) * 8),
          child: Transform.rotate(angle: sin(t) * 0.04, child: child),
        );
      },
      child: CardBack(width: widget.width),
    );
  }
}

/// Full screen reveal of pulled characters, one by one.
class PullRevealScreen extends StatefulWidget {
  const PullRevealScreen({super.key, required this.outcomes});

  final List<PullOutcome> outcomes;

  @override
  State<PullRevealScreen> createState() => _PullRevealScreenState();
}

class _PullRevealScreenState extends State<PullRevealScreen> with TickerProviderStateMixin {
  late final _charge = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  late final _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  int _index = 0;
  bool _summary = false;

  PullOutcome get _current => widget.outcomes[_index];

  @override
  void initState() {
    super.initState();
    _charge.addStatusListener((status) {
      if (status == AnimationStatus.completed) _flip.forward();
    });
    _flip.addStatusListener((status) {
      if (status == AnimationStatus.completed) _burst.forward();
    });
    _charge.forward();
  }

  @override
  void dispose() {
    _charge.dispose();
    _flip.dispose();
    _burst.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _advance() {
    if (_summary) return;
    if (!_flip.isCompleted) {
      _charge.value = 1;
      _flip.forward();
      return;
    }
    if (_index == widget.outcomes.length - 1) {
      setState(() => _summary = widget.outcomes.length > 1);
      if (!_summary) Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
    _flip.reset();
    _burst.reset();
    _charge.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.96),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _summary ? _buildSummary(context) : _buildReveal(context),
        ),
      ),
    );
  }

  Widget _buildReveal(BuildContext context) {
    final rarity = _current.card.rarity;
    return GestureDetector(
      key: const ValueKey('reveal'),
      behavior: HitTestBehavior.opaque,
      onTap: _advance,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_charge, _burst, _spin]),
              builder: (context, _) => CustomPaint(
                painter: _RaysPainter(
                  color: rarity.color,
                  intensity: _charge.value * 0.5 + _burst.value * 0.5,
                  rotation: _spin.value * 2 * pi,
                  rayCount: 6 + rarity.stars * 4,
                  burst: Curves.easeOut.transform(_burst.value),
                  sparkle: rarity.stars >= Rarity.hero.stars,
                ),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_charge, _flip]),
              builder: (context, _) {
                // The card shakes harder the rarer it is.
                final shake = _flip.value == 0
                    ? sin(_charge.value * pi * 18) * _charge.value * rarity.stars * 2.5
                    : 0.0;
                final angle = Curves.easeInOut.transform(_flip.value) * pi;
                final showFront = angle > pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..translateByDouble(shake, 0, 0, 1)
                    ..rotateY(showFront ? angle - pi : angle),
                  child: showFront ? _front(context) : const CardBack(width: 200),
                );
              },
            ),
          ),
          Positioned(
            top: 8,
            left: 16,
            right: 8,
            child: Row(
              children: [
                Text(
                  '${_index + 1} / ${widget.outcomes.length}',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (widget.outcomes.length > 1)
                  TextButton(
                    onPressed: () => setState(() => _summary = true),
                    child: const Text('Skip', style: TextStyle(color: Colors.white)),
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Text(
              'Tap to continue',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _front(BuildContext context) {
    final outcome = _current;
    final card = outcome.card;
    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _burst, curve: Curves.elasticOut)),
            child: Standee(card: card, width: 200),
          ),
          const SizedBox(height: 12),
          Nameplate(name: card.subject, title: card.title, rarity: card.rarity),
          const SizedBox(height: 12),
          FadeTransition(
            opacity: _burst,
            child: Chip(
              backgroundColor: outcome.isNew ? card.rarity.color : null,
              avatar: Icon(outcome.isNew ? Icons.fiber_new_rounded : Icons.upgrade_rounded),
              label: Text(outcome.isNew ? 'New character!' : 'Duplicate · +1 upgrade point (×${outcome.copies})'),
            ),
          ),
          Text('drawn by ${card.artist}', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey('summary'),
      children: [
        const SizedBox(height: 16),
        Text('Your pulls', style: textTheme.headlineSmall?.copyWith(color: Colors.white)),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (i, outcome) in widget.outcomes.indexed)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 300 + i * 80),
                      curve: Curves.easeOutBack,
                      builder: (context, value, child) => Transform.scale(scale: value, child: child),
                      child: SizedBox(
                        width: 104,
                        child: Column(
                          children: [
                            Standee(card: outcome.card, width: 88),
                            StarRow(rarity: outcome.card.rarity, size: 14),
                            Text(
                              outcome.card.subject,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              outcome.isNew ? 'NEW' : '+1 upgrade',
                              style: TextStyle(color: outcome.isNew ? outcome.card.rarity.color : Colors.white60),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ),
      ],
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter({
    required this.color,
    required this.intensity,
    required this.rotation,
    required this.rayCount,
    required this.burst,
    required this.sparkle,
  });

  final Color color;
  final double intensity;
  final double rotation;
  final int rayCount;
  final double burst;
  final bool sparkle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.longestSide;
    canvas.drawCircle(
      center,
      size.shortestSide * (0.2 + 0.25 * intensity),
      Paint()
        ..color = color.withValues(alpha: 0.6 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );
    final ray = Paint()..color = color.withValues(alpha: 0.18 * intensity);
    for (var i = 0; i < rayCount; i++) {
      final a = rotation + i * 2 * pi / rayCount;
      final spread = pi / rayCount * 0.45;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + cos(a - spread) * radius, center.dy + sin(a - spread) * radius)
        ..lineTo(center.dx + cos(a + spread) * radius, center.dy + sin(a + spread) * radius)
        ..close();
      canvas.drawPath(path, ray);
    }
    if (burst > 0 && burst < 1) {
      canvas.drawCircle(
        center,
        size.shortestSide * 0.6 * burst,
        Paint()
          ..color = color.withValues(alpha: 1 - burst)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * (1 - burst),
      );
      if (sparkle) {
        final random = Random(7);
        final dot = Paint()..color = Colors.white.withValues(alpha: 1 - burst);
        for (var i = 0; i < 40; i++) {
          final a = random.nextDouble() * 2 * pi;
          final d = size.shortestSide * (0.15 + random.nextDouble() * 0.5) * burst;
          canvas.drawCircle(center + Offset(cos(a), sin(a)) * d, 2 + random.nextDouble() * 3, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RaysPainter oldDelegate) => true;
}
