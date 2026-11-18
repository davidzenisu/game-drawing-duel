import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/screens/sign_in_screen.dart';
import 'package:frontend/game/screens/splash_screen.dart';
import 'package:frontend/game/widgets/sponsor_banner.dart';

import '../helpers.dart';

void main() {
  testWidgets('the title screen shows the sponsor banner between the title and Tap to start', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: SplashScreen(ready: true, onStart: () {})));
    await tester.pump(SplashScreen.intro);
    expect(find.text("SPONSORED BY OLIVIA'S CLAUDE SUBSCRIPTION"), findsOneWidget);
    final banner = tester.getRect(find.byType(SponsorBanner));
    expect(banner.top, greaterThan(tester.getBottomLeft(find.text('DRAWING DUEL')).dy));
    expect(banner.bottom, lessThan(tester.getTopLeft(find.text('Tap to start')).dy));
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the sign-in screen and the daily hub have no sponsor banner', (tester) async {
    final controller = await launchedGame(launchDate: firstMonday);
    await tester.pumpWidget(MaterialApp(home: SignInScreen(controller: controller)));
    expect(find.byType(SponsorBanner), findsNothing);
    await tester.pumpWidget(MaterialApp(home: DailyHubScreen(controller: controller)));
    await tester.pump();
    expect(find.byType(SponsorBanner), findsNothing);
  });
}
