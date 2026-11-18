import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/screens/sign_in_screen.dart';
import 'package:frontend/game/widgets/sponsor_banner.dart';

import '../helpers.dart';

void main() {
  testWidgets('the sign-in screen shows the sponsor banner above the sign-in card', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: SignInScreen(controller: await launchedGame(launchDate: firstMonday))));
    expect(find.text("SPONSORED BY OLIVIA'S CLAUDE SUBSCRIPTION"), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(SponsorBanner)).dy,
      lessThan(tester.getTopLeft(find.byType(Card)).dy),
    );
    expect(tester.takeException(), isNull, reason: 'fits a phone');
  });

  testWidgets('the daily hub has no sponsor banner', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: await launchedGame(launchDate: firstMonday))));
    await tester.pump();
    expect(find.byType(SponsorBanner), findsNothing);
  });
}
