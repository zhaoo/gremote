// Run with `flutter test tool/render_frame_previews.dart`.
// GREMOTE_QA_FONT optionally supplies a local CJK font for host rendering.
// GREMOTE_QA_OUTPUT selects the output folder (default build/frame-previews).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/frame/frame_layout.dart';
import 'package:gremote/darkroom/frame/frame_painter.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';

void main() {
  testWidgets('render frame contact sheet using production painter',
      (tester) async {
    await tester.runAsync(() async {
      final font = Platform.environment['GREMOTE_QA_FONT'];
      if (font != null) {
        final bytes = await File(font).readAsBytes();
        for (final family in ['MiSans', 'sans-serif', 'monospace']) {
          await (FontLoader(family)
                ..addFont(Future.value(ByteData.sublistView(bytes))))
              .load();
        }
      }
      await (FontLoader('GRemoteEditorial')
            ..addFont(
                rootBundle.load('assets/fonts/gremote_editorial_serif.ttf')))
          .load();
      final codec = await ui.instantiateImageCodec(
          await File('assets/images/street_moment.jpg').readAsBytes());
      final photo = (await codec.getNextFrame()).image;
      codec.dispose();
      final output = Directory(
          Platform.environment['GREMOTE_QA_OUTPUT'] ?? 'build/frame-previews');
      await output.create(recursive: true);
      const styles = [
        FrameStyle.none,
        FrameStyle.classic,
        FrameStyle.street,
        FrameStyle.contact
      ];
      for (final portrait in [false, true]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final width = portrait ? 500 : 700;
        final height = portrait ? 750 : 467;
        final cellWidth = width + 100;
        final cellHeight = height + 160;
        final sheetWidth = cellWidth * 2;
        final sheetHeight = cellHeight * 2;
        canvas.drawRect(
            Rect.fromLTWH(0, 0, sheetWidth.toDouble(), sheetHeight.toDouble()),
            Paint()..color = const Color(0xFFE7E8E4));
        for (var i = 0; i < styles.length; i++) {
          final style = styles[i];
          final layout = computeFrameLayout(
              photoWidth: width,
              photoHeight: height,
              style: style,
              ratio: FrameRatio.original,
              content: const FrameContent(
                  model: 'RICOH GR III',
                  params: '28mm f/2.8 1/250s ISO200',
                  date: '2026.10.13',
                  title: '午后的一束光',
                  location: '街头'));
          final x = (i % 2) * cellWidth + 30.0;
          final y = (i ~/ 2) * cellHeight + 20.0;
          final label = TextPainter(
              text: TextSpan(
                  text: style.label,
                  style: const TextStyle(
                      fontFamily: 'MiSans',
                      color: Color(0xFF353C38),
                      fontSize: 22)),
              textDirection: TextDirection.ltr)
            ..layout();
          label.paint(canvas, Offset(x, y));
          label.dispose();
          canvas.save();
          canvas.translate(x, y + 40);
          canvas.drawRect(
              Rect.fromLTWH(0, 0, layout.canvasWidth.toDouble(),
                  layout.canvasHeight.toDouble()),
              Paint()..color = Color(layout.background));
          final p = layout.photo;
          // Portrait QA uses a central crop as its source photo; the frame
          // itself always preserves the entire supplied photo rectangle.
          final source = portrait
              ? Rect.fromLTWH(photo.width * 0.4, 0, photo.height * 2 / 3,
                  photo.height.toDouble())
              : Rect.fromLTWH(
                  0, 0, photo.width.toDouble(), photo.height.toDouble());
          canvas.drawImageRect(
              photo,
              source,
              Rect.fromLTWH(p.x.toDouble(), p.y.toDouble(), p.width.toDouble(),
                  p.height.toDouble()),
              Paint()..filterQuality = FilterQuality.high);
          for (final overlay in layout.overlays) {
            canvas.save();
            canvas.translate(
                overlay.rect.x.toDouble(), overlay.rect.y.toDouble());
            canvas.clipRect(Rect.fromLTWH(0, 0, overlay.rect.width.toDouble(),
                overlay.rect.height.toDouble()));
            FramePainter.paintOverlay(canvas, overlay);
            canvas.restore();
          }
          canvas.restore();
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(sheetWidth, sheetHeight);
        picture.dispose();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File(
                '${output.path}/frame-styles-${portrait ? 'portrait' : 'landscape'}.png')
            .writeAsBytes(
                png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
      }
      photo.dispose();
    });
  });
}
