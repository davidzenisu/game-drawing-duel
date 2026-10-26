import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/upgrades.dart';
import 'package:frontend/game/widgets/stroke_effects.dart';
import 'package:frontend/theme/palette.dart';

void main() {
  test('the glow takes the element colour only while the element is shown', () {
    const accent = AppPalette.brushBlue;
    const shown = [UpgradeEffect.light, UpgradeEffect.element, UpgradeEffect.echo];
    expect(glowColor(shown, ElementKind.fire, accent), AppPalette.elementFire);
    // The element switched off, or not unlocked yet.
    const hidden = [UpgradeEffect.light, UpgradeEffect.echo];
    expect(glowColor(hidden, ElementKind.fire, accent), accent);
    expect(glowColor(shown, null, accent), accent);
  });
}
