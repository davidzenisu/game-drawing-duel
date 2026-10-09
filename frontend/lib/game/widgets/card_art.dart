import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/models.dart';
import '../rules/upgrades.dart';
import 'sketch_canvas.dart';
import 'stroke_effects.dart';

export 'stroke_effects.dart' show elementColor;

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
                Positioned.fill(
                  child: CardboardCard(
                    shadow: effects.contains(UpgradeEffect.shadow),
                    child: effects.isEmpty
                        ? SketchView(card.sketch)
                        : EffectSketchView(
                            sketch: card.sketch,
                            effects: effects,
                            element: element,
                            accent: card.rarity.color,
                          ),
                  ),
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
