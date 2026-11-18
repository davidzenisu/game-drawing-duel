import 'package:flutter/material.dart';

/// The sponsor's banner, big on the sign-in screen.
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFD97757), Color(0xFFB8532F)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 34,
            height: 1.1,
            letterSpacing: 2,
            color: Colors.white,
            shadows: [Shadow(color: Color(0xFF5A2310), offset: Offset(3, 3))],
          ),
        ),
      ),
    );
  }
}
