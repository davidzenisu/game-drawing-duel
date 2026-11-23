import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/sound.dart';
import 'package:frontend/game/widgets/account_menu.dart';
import 'package:frontend/mockup/mock_game_session.dart';

void main() {
  testWidgets('sound is off until turned on in the account menu, and off again from there', (tester) async {
    addTearDown(() => sound.setEnabled(false));
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [AccountMenu(session: game)]),
        ),
      ),
    );
    expect(sound.enabled.value, isFalse);
    sound.played.clear();
    sound.starDrop();
    expect(sound.played, isEmpty, reason: 'nothing plays while sound is off');

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound: off'));
    await tester.pumpAndSettle();
    expect(sound.enabled.value, isTrue);
    sound.starDrop();
    expect(sound.played, ['star_drop.mp3']);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    await tester.tap(find.text('Sound: on'));
    await tester.pumpAndSettle();
    expect(sound.enabled.value, isFalse);
  });

  test('every sound the game plays is bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sound.setEnabled(true);
    addTearDown(() => sound.setEnabled(false));
    sound.played.clear();
    sound
      ..timerTick()
      ..timerFinal()
      ..timeUp()
      ..drawingSaved()
      ..starDrop()
      ..fightResult(won: true)
      ..fightResult(won: false)
      ..boxLands()
      ..tapeTearing()
      ..tapeCut()
      ..cardFlips();
    for (final rarity in Rarity.values) {
      sound
        ..boxShakes(rarity)
        ..boxOpens(rarity)
        ..cardRises(rarity)
        ..cardRevealed(rarity);
    }
    for (final file in [...sound.played, 'music.wav']) {
      final data = await rootBundle.load('assets/sounds/$file');
      expect(data.lengthInBytes, greaterThan(0), reason: file);
    }
  });
}
