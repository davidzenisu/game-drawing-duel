import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../logic/models.dart';
import '../logic/upgrades.dart';
import 'sketch_canvas.dart';

Color elementColor(ElementKind element) => switch (element) {
  ElementKind.fire => AppPalette.elementFire,
  ElementKind.ice => AppPalette.elementIce,
  ElementKind.storm => AppPalette.elementStorm,
};

/// A white cardboard card that holds a drawing.
class CardboardCard extends StatelessWidget {
  const CardboardCard({super.key, required this.child, this.shadow = false});

  final Widget child;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: cardAspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppPalette.cardboard,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppPalette.cardboardEdge, width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 2)),
            if (shadow)
              BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 18, offset: const Offset(10, 14)),
          ],
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: child),
      ),
    );
  }
}

/// A character slotted into a plastic standee base, decorated with the
/// effects unlocked through duplicates.
class Standee extends StatelessWidget {
  const Standee({super.key, required this.card, this.width = 140, this.effects = const [], this.element});

  final CharacterCard card;
  final double width;
  final List<UpgradeEffect> effects;
  final ElementKind? element;

  @override
  Widget build(BuildContext context) {
    final cardHeight = width / cardAspectRatio;
    final auraColor = element != null ? elementColor(element!) : card.rarity.color;
    final hasAura = effects.contains(UpgradeEffect.element);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width,
            height: cardHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (effects.contains(UpgradeEffect.light))
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: auraColor.withValues(alpha: 0.7),
                            blurRadius: width * 0.3,
                            spreadRadius: width * 0.05,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (hasAura)
                  Positioned.fill(
                    child: ElementalAura(color: auraColor, strong: effects.contains(UpgradeEffect.aura)),
                  ),
                Positioned.fill(
                  child: CardboardCard(shadow: effects.contains(UpgradeEffect.shadow), child: SketchView(card.sketch)),
                ),
                if (effects.contains(UpgradeEffect.halo))
                  Positioned(
                    top: -width * 0.16,
                    left: width * 0.2,
                    right: width * 0.2,
                    height: width * 0.14,
                    child: const _Halo(),
                  ),
              ],
            ),
          ),
          StandeeBase(width: width * 0.62),
        ],
      ),
    );
  }
}

class StandeeBase extends StatelessWidget {
  const StandeeBase({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(width, width * 0.32), painter: _BasePainter());
  }
}

class _BasePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final slot = Rect.fromLTWH(size.width * 0.1, 0, size.width * 0.8, size.height * 0.35);
    final disc = Rect.fromLTWH(0, size.height * 0.2, size.width, size.height * 0.8);
    canvas.drawOval(disc.shift(const Offset(0, 3)), Paint()..color = Colors.black.withValues(alpha: 0.25));
    canvas.drawOval(disc, Paint()..color = AppPalette.plasticShade);
    canvas.drawOval(
      Rect.fromLTWH(disc.left, disc.top, disc.width, disc.height * 0.8),
      Paint()..color = AppPalette.plastic,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(slot, const Radius.circular(3)), Paint()..color = AppPalette.plasticShade);
    canvas.drawRRect(
      RRect.fromRectAndRadius(slot.deflate(2), const Radius.circular(2)),
      Paint()..color = AppPalette.plastic,
    );
    canvas.drawArc(
      Rect.fromLTWH(disc.left + size.width * 0.12, disc.top + 2, disc.width * 0.5, disc.height * 0.5),
      pi * 1.05,
      pi * 0.5,
      false,
      Paint()
        ..color = AppPalette.plasticHighlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BasePainter oldDelegate) => false;
}

class _Halo extends StatelessWidget {
  const _Halo();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const OvalBorder(side: BorderSide(color: AppPalette.rarityLegend, width: 4)),
        shadows: [BoxShadow(color: AppPalette.rarityLegend.withValues(alpha: 0.8), blurRadius: 12)],
      ),
    );
  }
}

/// Animated, hand-drawn looking flames around a card.
class ElementalAura extends StatefulWidget {
  const ElementalAura({super.key, required this.color, this.strong = false});

  final Color color;
  final bool strong;

  @override
  State<ElementalAura> createState() => _ElementalAuraState();
}

class _ElementalAuraState extends State<ElementalAura> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _AuraPainter(_controller, widget.color, widget.strong)));
  }
}

class _AuraPainter extends CustomPainter {
  _AuraPainter(this.animation, this.color, this.strong) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final bool strong;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * 2 * pi;
    final count = strong ? 18 : 11;
    final reach = size.width * (strong ? 0.22 : 0.14);
    final paint = Paint()
      ..color = color.withValues(alpha: strong ? 0.75 : 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final rect = Offset.zero & size;
    for (var i = 0; i < count; i++) {
      final f = i / count;
      final perimeter = 2 * (size.width + size.height);
      var d = f * perimeter;
      Offset base;
      Offset dir;
      if (d < size.width) {
        base = Offset(d, 0);
        dir = const Offset(0, -1);
      } else if ((d -= size.width) < size.height) {
        base = Offset(size.width, d);
        dir = const Offset(1, 0);
      } else if ((d -= size.height) < size.width) {
        base = Offset(size.width - d, size.height);
        dir = const Offset(0, 1);
      } else {
        d -= size.width;
        base = Offset(0, size.height - d);
        dir = const Offset(-1, 0);
      }
      final flicker = 0.6 + 0.4 * sin(t * 2 + i * 1.7);
      final tip = base + dir * reach * flicker + Offset(sin(t + i) * 4, cos(t + i) * 4);
      final normal = Offset(-dir.dy, dir.dx) * size.width * 0.07;
      final path = Path()
        ..moveTo(base.dx - normal.dx, base.dy - normal.dy)
        ..quadraticBezierTo(tip.dx - normal.dx * 0.3, tip.dy - normal.dy * 0.3, tip.dx, tip.dy)
        ..quadraticBezierTo(
          tip.dx + normal.dx * 0.3,
          tip.dy + normal.dy * 0.3,
          base.dx + normal.dx,
          base.dy + normal.dy,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.drawRect(
      rect.inflate(2),
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(_AuraPainter oldDelegate) => oldDelegate.color != color || oldDelegate.strong != strong;
}

/// JRPG-style nameplate as seen in `docs/images`.
class Nameplate extends StatelessWidget {
  const Nameplate({
    super.key,
    required this.name,
    required this.title,
    this.rarity,
    this.compact = false,
    this.nameFirst = false,
    this.large = false,
  });

  final String name;
  final String title;
  final Rarity? rarity;
  final bool compact;

  /// Shows the name above the title, as on a challenger's nameplate.
  final bool nameFirst;

  /// Extra large text for the challenger in a fight.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle =
        (compact
                ? textTheme.labelSmall
                : large
                ? textTheme.titleLarge
                : textTheme.titleSmall)!
            .copyWith(color: AppPalette.nameplateText, fontFamily: 'monospace', fontWeight: FontWeight.w700);
    final nameStyle =
        (compact
                ? textTheme.titleMedium
                : large
                ? textTheme.displaySmall
                : textTheme.headlineSmall)!
            .copyWith(
              color: AppPalette.nameplateText,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppPalette.nameplateTop, AppPalette.nameplateBottom],
        ),
        borderRadius: BorderRadius.circular(compact ? 10 : 16),
        border: Border.all(color: AppPalette.nameplateBorder, width: compact ? 2 : 3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: compact ? 6 : 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rarity != null) StarRow(rarity: rarity!, size: compact ? 12 : 16),
            if (!nameFirst) Text(title, style: titleStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (large)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(name, style: nameStyle, maxLines: 1),
              )
            else
              Text(name, style: nameStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (nameFirst) Text(title, style: titleStyle, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rarity, this.size = 16});

  final Rarity rarity;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < rarity.stars; i++) Icon(Icons.star_rounded, size: size, color: rarity.color)],
    );
  }
}
