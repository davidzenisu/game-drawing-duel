import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/game/screens/daily_hub_screen.dart';
import 'package:frontend/game/screens/sign_in_screen.dart';
import 'package:frontend/game/screens/splash_screen.dart';
import 'package:frontend/game/widgets/sponsor_banner.dart';

import '../helpers.dart';

void main() {
  testWidgets('the sponsor banner slides in below Tap to start, a while after everything else', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    double bannerOpacity() => tester
        .widget<Opacity>(find.ancestor(of: find.byType(SponsorBanner), matching: find.byType(Opacity)).first)
        .opacity;

    await tester.pumpWidget(MaterialApp(home: SplashScreen(ready: true, onStart: () {})));
    await tester.pump(SplashScreen.intro);
    await tester.pump();
    // Everything else is in; the banner waits a moment longer.
    expect(bannerOpacity(), 0);
    await tester.pump(SplashScreen.bannerPause - const Duration(milliseconds: 100));
    expect(bannerOpacity(), 0);
    // Then it slides up from below.
    await tester.pump(const Duration(milliseconds: 300));
    final sliding = tester.getRect(find.byType(SponsorBanner)).top;
    expect(bannerOpacity(), greaterThan(0));
    await tester.pump(SplashScreen.banner);
    expect(bannerOpacity(), 1);
    expect(tester.getRect(find.byType(SponsorBanner)).top, lessThan(sliding));
    expect(find.text("SPONSORED BY OLIVIA'S CLAUDE SUBSCRIPTION"), findsOneWidget);
    expect(
      tester.getRect(find.byType(SponsorBanner)).top,
      greaterThan(tester.getBottomLeft(find.text('Tap to start')).dy),
    );
    expect(tester.takeException(), isNull, reason: 'fits a phone');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tap to start can be tapped while the banner comes in', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var started = 0;
    await tester.pumpWidget(MaterialApp(home: SplashScreen(ready: true, onStart: () => started++)));
    await tester.pump(SplashScreen.intro);
    await tester.pump();
    await tester.tap(find.text('Tap to start'));
    expect(started, 1);
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
