import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/sound.dart';
import 'package:frontend/game/widgets/account_menu.dart';
import 'package:frontend/mockup/mock_game_session.dart';

Future<void> _choose(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('Account'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('music and sound effects are each off until turned on in the account menu', (tester) async {
    addTearDown(() {
      sound
        ..setMusic(false)
        ..setEffects(false);
    });
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(appBar: AppBar(actions: [AccountMenu(session: game)])),
      ),
    );
    expect((sound.music.value, sound.effects.value), (false, false));
    sound.played.clear();
    sound.starDrop();
    expect(sound.played, isEmpty, reason: 'no sound effects while they are off');

    // Music on: the effects stay off.
    await _choose(tester, 'Music: off');
    expect((sound.music.value, sound.effects.value), (true, false));
    sound.starDrop();
    expect(sound.played, isEmpty);

    // Effects on too, then music off again: the effects stay on.
    await _choose(tester, 'Sound effects: off');
    expect((sound.music.value, sound.effects.value), (true, true));
    sound.starDrop();
    expect(sound.played, ['star_drop.mp3']);
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    await tester.tap(find.text('Music: on'));
    await tester.pumpAndSettle();
    expect((sound.music.value, sound.effects.value), (false, true));

    await _choose(tester, 'Sound effects: on');
    expect((sound.music.value, sound.effects.value), (false, false));
  });

  test('every sound the game plays is bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sound.setEffects(true);
    addTearDown(() => sound.setEffects(false));
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
