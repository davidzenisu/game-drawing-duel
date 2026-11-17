import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/game_session.dart';
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
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    // Remove your own, once confirmed.
    await tester.tap(find.text('Hub flickers'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this suggestion?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Hub flickers'), findsNothing);
    expect((await game.suggestions()).map((s) => s.title), isNot(contains('Hub flickers')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('admins set a status; the author confirms it fixed; done ones hide unless all show', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await launchedGame();
    final mine = await game.suggest(kind: SuggestionKind.bug, title: 'Hub flickers', description: 'After a fight.');
    await tester.pumpWidget(MaterialApp(home: SuggestionsScreen(session: game)));
    await tester.pumpAndSettle();
    expect(find.text('In progress'), findsOneWidget, reason: "the friend's bug report");
    expect(find.text('Open'), findsNWidgets(2));

    // The mockup's player sets their own to in review, like a server admin.
    await tester.tap(find.text('Hub flickers'));
    await tester.pumpAndSettle();
    expect(find.text("It's fixed now"), findsNothing, reason: 'not in review yet');
    await tester.tap(find.byType(DropdownMenu<SuggestionStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In review').last);
    await tester.pumpAndSettle();
    expect((await game.suggestions()).firstWhere((s) => s.id == mine.id).status, SuggestionStatus.inReview);

    // It works now: done, and a pull waits on the notification board.
    final gifts = game.gifts.length;
    await tester.tap(find.text("It's fixed now"));
    await tester.pumpAndSettle();
    expect(find.text("It's fixed now"), findsNothing);
    expect(find.byType(DropdownMenu<SuggestionStatus>), findsNothing, reason: 'done stays done');
    expect(find.textContaining('A pull is waiting for you'), findsOneWidget);
    expect(game.gifts, hasLength(gifts + 1));
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    // Done ones only show with "Show all".
    expect(find.text('Hub flickers'), findsNothing);
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text('Hub flickers'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
