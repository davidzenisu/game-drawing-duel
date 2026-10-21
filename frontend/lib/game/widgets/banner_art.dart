import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../rules/gacha.dart';
import '../rules/models.dart';
import 'card_art.dart';

/// A gacha banner: its featured characters as standees in 3D space, swaying
/// gently, behind the banner's name in word art.
///
/// [parallax] is how far the banner is from the middle of a carousel, in
/// pages; the characters drift with it, the closer ones more.
class BannerArt extends StatefulWidget {
  const BannerArt({
    super.key,
    required this.banner,
    required this.featured,
    this.caption,
    this.locked = false,
    this.parallax = 0,
  });

  final GachaBanner banner;
  final List<CharacterCard> featured;
  final String? caption;

  /// Not open yet: greyed out, with a lock.
  final bool locked;
  final double parallax;

  @override
  State<BannerArt> createState() => _BannerArtState();
}

class _BannerArtState extends State<BannerArt> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _BannerStyle.of(widget.banner);
    final art = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * 2 * pi;
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: style.background,
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _SparklePainter(color: style.glow, t: _controller.value),
                ),
                // The floor the standees stand on.
                Align(
                  alignment: const Alignment(0, 1.25),
                  child: Container(
                    width: size.width * 1.1,
                    height: size.height * 0.45,
                    decoration: BoxDecoration(
                      shape: BoxShape.rectangle,
                      gradient: RadialGradient(
                        colors: [style.glow.withValues(alpha: 0.45), style.glow.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                for (final slot in _slots(widget.featured.length)) _standee(slot, size, t),
                Align(
                  alignment: const Alignment(0, 0.42),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
                    child: WordArt(
                      widget.banner.label.toUpperCase(),
                      colors: style.title,
                      angle: -0.06 + sin(t) * 0.01,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _Kicker(text: style.kicker, color: style.glow),
                  ),
                ),
                if (widget.caption case final caption?)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xAA000000)],
                        ),
                      ),
                      child: Text(
                        caption,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: widget.locked
          ? Stack(
              fit: StackFit.expand,
              children: [
                ColorFiltered(
                  colorFilter: _greyscale,
                  child: TickerMode(enabled: false, child: art),
                ),
                const ColoredBox(color: Color(0x66000000)),
                const Align(
                  alignment: Alignment(0, -0.45),
                  child: Icon(Icons.lock_rounded, size: 48, color: Colors.white70),
                ),
              ],
            )
          : art,
    );
  }

  Widget _standee(_Slot slot, Size size, double t) {
    final card = widget.featured[slot.index];
    final width = size.height * 0.44;
    // Closer standees sway and drift more.
    final depth = 1 - slot.z / 400;
    final sway = sin(t + slot.index * 1.7) * 0.12;
    final bob = sin(t * 2 + slot.index) * 4;
    return Align(
      alignment: Alignment(slot.x - widget.parallax * 0.5 * depth, -0.1),
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0022)
          ..translateByDouble(0, bob - slot.z * 0.12, slot.z, 1)
          ..rotateY(slot.angle + sway),
        child: Standee(card: card, width: width),
      ),
    );
  }

  /// Where each of [count] standees stands, the farthest first so the
  /// closer ones are drawn over them.
  static List<_Slot> _slots(int count) => switch (count) {
    0 => const [],
    1 => const [_Slot(0, 0, 60, 0)],
    2 => const [_Slot(0, -0.5, 40, 0.4), _Slot(1, 0.5, 40, -0.4)],
    // In an arc: the middle ones farther back, the outer ones turned inwards.
    _ => [
      for (var i = 0; i < count; i++)
        () {
          final x = -0.65 + 1.3 * i / (count - 1);
          return _Slot(i, x, 20 + 80 * (1 - x.abs() / 0.65), -x * 0.75);
        }(),
    ]..sort((a, b) => b.z.compareTo(a.z)),
  };
}

const _greyscale = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// A standee's place on a banner: [x] from -1 (left) to 1 (right), [z] how
/// far back it stands and [angle] how much it turns towards the middle.
class _Slot {
  const _Slot(this.index, this.x, this.z, this.angle);

  final int index;
  final double x;
  final double z;
  final double angle;
}

class _BannerStyle {
  const _BannerStyle({required this.background, required this.glow, required this.title, required this.kicker});

  final List<Color> background;
  final Color glow;
  final List<Color> title;
  final String kicker;

  static _BannerStyle of(GachaBanner banner) => switch (banner) {
    GachaBanner.standard => const _BannerStyle(
      background: [Color(0xFF0A0B4D), Color(0xFF2B2F9E), Color(0xFF12134F)],
      glow: AppPalette.rarityLegend,
      title: [Color(0xFFFFF4C2), AppPalette.rarityLegend, Color(0xFFFF8A3D)],
      kicker: 'ALWAYS OPEN',
    ),
    GachaBanner.weekly => const _BannerStyle(
      background: [Color(0xFF2A0B4D), Color(0xFF7A2DB8), Color(0xFFB8327A)],
      glow: Color(0xFFFF7AD9),
      title: [Color(0xFFFFFFFF), Color(0xFFFFB3EC), AppPalette.rarityHero],
      kicker: 'RATE UP',
    ),
  };
}

/// Big, bold, outlined and slanted: a banner's name.
class WordArt extends StatelessWidget {
  const WordArt(this.text, {super.key, required this.colors, this.angle = -0.06});

  final String text;
  final List<Color> colors;
  final double angle;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontSize: 64,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      letterSpacing: 2,
      height: 1,
    );
    return Transform.rotate(
      angle: angle,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Stack(
          children: [
            Text(
              text,
              style: base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 10
                  ..strokeJoin = StrokeJoin.round
                  ..color = const Color(0xFF14082E),
                shadows: const [Shadow(color: Color(0x99000000), offset: Offset(0, 6), blurRadius: 8)],
              ),
            ),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
              ).createShader(bounds),
              child: Text(text, style: base.copyWith(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
      ),
    );
  }
}

/// Twinkling dots, always in the same places.
class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(7);
    for (var i = 0; i < 28; i++) {
      final position = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height * 0.7);
      final twinkle = (sin((t + random.nextDouble()) * 2 * pi) + 1) / 2;
      canvas.drawCircle(
        position,
        1 + random.nextDouble() * 1.8,
        Paint()..color = color.withValues(alpha: 0.15 + twinkle * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t || old.color != color;
}
