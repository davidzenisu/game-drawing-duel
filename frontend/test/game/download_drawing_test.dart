import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/widgets/download_drawing_button.dart';
import 'package:frontend/game/widgets/sketch_canvas.dart';
import 'package:frontend/theme/palette.dart';

import '../helpers.dart';

CharacterCard _card({String subject = 'Kim', String title = 'Baron of the Brunch Table'}) => CharacterCard(
  id: 'c1',
  subject: subject,
  title: title,
  rarity: Rarity.basic,
  prompt: 'Basic',
  artist: 'Robin',
  sketch: doodle,
);

void main() {
  testWidgets('the drawing renders as a PNG on its cardboard card, like in the app', (tester) async {
    await tester.runAsync(() async {
      final png = await sketchPng(doodle, width: 400);
      // The PNG signature, then the image it decodes to.
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      expect((image.width, image.height), (400, 500));
      final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      // A corner is cardboard; the diagonal stroke is ink.
      Color at(int x, int y) {
        final i = (y * image.width + x) * 4;
        return Color.fromARGB(
          pixels.getUint8(i + 3),
          pixels.getUint8(i),
          pixels.getUint8(i + 1),
          pixels.getUint8(i + 2),
        );
      }

      expect(at(399, 0), AppPalette.cardboard);
      expect(at(200, 250), const Color(0xFF000000));
      image.dispose();
    });
  });

  test('downloads are named after the character', () {
    expect(DownloadDrawingButton.fileName('Kim', 'Baron of the Brunch Table'), 'Kim - Baron of the Brunch Table.png');
    expect(DownloadDrawingButton.fileName('Kim', 'AC/DC: "Live"?'), 'Kim - ACDC Live.png');
  });

  testWidgets('the button only shows where the browser can download', (tester) async {
    Widget app(bool available) => MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [DownloadDrawingButton.card(_card(), available: available)]),
      ),
    );
    await tester.pumpWidget(app(false));
    expect(find.byTooltip('Download drawing'), findsNothing, reason: 'not on the test VM');
    await tester.pumpWidget(app(true));
    expect(find.byTooltip('Download drawing'), findsOneWidget);
  });
}
