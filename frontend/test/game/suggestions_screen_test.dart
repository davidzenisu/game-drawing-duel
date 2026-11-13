import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/screens/suggestions_screen.dart';
import 'package:frontend/game/tutorials.dart';

import '../helpers.dart';

void main() {
  testWidgets('the account menu leads to the board: post an idea, open one and upvote it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame();
    for (final tutorial in Tutorial.values) {
      await game.markTutorialSeen(tutorial.key);
    }
    await tester.pumpWidget(GameApp(session: game, splash: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Let's go"));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ideas & bugs'));
    await tester.pumpAndSettle();
    expect(find.byType(SuggestionsScreen), findsOneWidget);
    expect(find.text('A dark mode for the canvas'), findsOneWidget);
    expect(find.text('Undo removes two strokes'), findsOneWidget);

    // Post a bug report.
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();
    final post = find.widgetWithText(FilledButton, 'Post');
    expect(tester.widget<FilledButton>(post).onPressed, isNull, reason: 'needs a title and a description');
    await tester.tap(find.text('Bug'));
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Hub flickers');
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'When I come back from a fight.');
    await tester.pump();
    await tester.tap(post);
    await tester.pumpAndSettle();
    expect(find.text('Hub flickers'), findsOneWidget);
    expect(find.textContaining('by you'), findsOneWidget);

    // Open the friend's bug report and upvote it.
    await tester.tap(find.text('Undo removes two strokes'));
    await tester.pumpAndSettle();
    expect(find.text('Sometimes one tap on undo takes away the last two strokes instead of one.'), findsOneWidget);
    await tester.tap(find.text('Upvote · 0 upvotes'));
    await tester.pumpAndSettle();
    expect(find.text('Upvoted · 1 upvote'), findsOneWidget);
    expect((await game.suggestions()).firstWhere((s) => s.title == 'Undo removes two strokes').voted, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
