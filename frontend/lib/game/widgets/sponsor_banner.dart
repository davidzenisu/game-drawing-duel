import 'package:flutter/material.dart';

/// The sponsor's banner on the title screen, below Tap to start.
class SponsorBanner extends StatelessWidget {
  const SponsorBanner({super.key});

  static const text = "SPONSORED BY OLIVIA'S CLAUDE SUBSCRIPTION";

  /// A bold comic-book face, bundled with the app (SIL Open Font License).
  static const fontFamily = 'Bangers';

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.03,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFD97757), Color(0xFFB8532F)]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2))],
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 17,
            height: 1.1,
            letterSpacing: 1,
            color: Colors.white,
            shadows: [Shadow(color: Color(0xFF5A2310), offset: Offset(1.5, 1.5))],
          ),
        ),
      ),
    );
  }
}
