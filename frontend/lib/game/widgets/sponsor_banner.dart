import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import 'banner_art.dart';

/// The sponsor's banner on the title screen, below Tap to start: word art
/// like the summon banners' names, in the standard banner's gold.
class SponsorBanner extends StatelessWidget {
  const SponsorBanner({super.key});

  static const text = "SPONSORED BY OLIVIA'S CLAUDE SUBSCRIPTION";

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      child: const ExcludeSemantics(
        child: WordArt(
          "SPONSORED BY\nOLIVIA'S CLAUDE\nSUBSCRIPTION",
          colors: [Color(0xFFFFF4C2), AppPalette.rarityLegend, Color(0xFFFF8A3D)],
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
