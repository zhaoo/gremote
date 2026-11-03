import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/app/widgets/brand_wordmark.dart';

void main() {
  for (final dark in [true, false]) {
    testWidgets(
        'brand renders actual transparent background in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: dark ? GRemoteTheme.dark : GRemoteTheme.light,
          home: Center(
              child: RepaintBoundary(
                  key: key, child: const BrandWordmark(width: 288)))));
      await tester.runAsync(() async {
        // Await the real asset decoder before capturing the composited layer.
        await precacheImage(
            const AssetImage('assets/images/gremote_brand_editorial.png'),
            tester.element(find.byType(BrandWordmark)));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        expect(bytes[3], 0,
            reason: 'upper-left background must be transparent');
        expect(bytes[bytes.length - 1], 0,
            reason: 'lower-right background must be transparent');
        var opaque = 0, edge = 0;
        for (var p = 0; p < bytes.length; p += 4) {
          if (bytes[p + 3] == 255) {
            opaque++;
            expect(bytes[p], dark ? 239 : 34);
          } else if (bytes[p + 3] > 0) {
            edge++;
          }
        }
        expect(opaque, greaterThan(100));
        expect(edge, greaterThan(100));
        image.dispose();
      });
    });
  }
}
