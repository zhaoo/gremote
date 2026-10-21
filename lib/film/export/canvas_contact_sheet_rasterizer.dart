import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import '../../imaging/imaging_engine.dart';
import '../model/film_roll.dart';
import 'contact_sheet_exporter.dart';
import 'contact_sheet_layout.dart';

class CanvasContactSheetRasterizer implements ContactSheetRasterizer {
  const CanvasContactSheetRasterizer();
  @override
  Future<ContactSheetRaster> rasterize(FilmRoll roll, ContactSheetPage page,
      List<ContactSheetCell> cells) async {
    final recorder = ui.PictureRecorder();
    var missing = 0;
    // Keep each decoded image alive only until the page has been rasterized.
    final draw = Canvas(recorder), images = <ui.Image>[];
    void text(String label, double x, double y, double size, Color color,
        {double width = 1300}) {
      final p = TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(
                  fontFamily: 'sans-serif', fontSize: size, color: color)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…')
        ..layout(maxWidth: width);
      p.paint(draw, Offset(x, y));
      p.dispose();
    }

    try {
      draw.drawColor(const Color(0xff131a16), BlendMode.src);
      text(roll.name, 48, 42, 36, const Color(0xfff1eadb));
      text('GREMOTE · 数字胶卷 / ${page.index + 1}', 48, 98, 17,
          const Color(0xffbcaa80));
      for (var i = 0; i < cells.length; i++) {
        final cell = cells[i],
            x = 48.0 + (i % 4) * 340,
            y = 160.0 + (i ~/ 4) * 268;
        final rect = Rect.fromLTWH(x, y, 324, 216);
        draw.drawRect(rect, Paint()..color = const Color(0xff27322b));
        ui.Image? image;
        if (cell.thumbnail != null) {
          ui.Codec? codec;
          try {
            codec = await ui.instantiateImageCodec(cell.thumbnail!,
                targetWidth: 324, targetHeight: 216, allowUpscaling: false);
            image = (await codec.getNextFrame()).image;
            images.add(image);
            final fit = applyBoxFit(
                BoxFit.cover,
                Size(image.width.toDouble(), image.height.toDouble()),
                rect.size);
            final src = Alignment.center.inscribe(
                fit.source,
                Offset.zero &
                    Size(image.width.toDouble(), image.height.toDouble()));
            draw.drawImageRect(image, src, rect,
                Paint()..filterQuality = FilterQuality.medium);
          } catch (_) {
            /* Corrupt thumbnail is a visible placeholder. */
          } finally {
            codec?.dispose();
          }
        }
        if (image == null) {
          missing++;
          text('原片暂不可用', x + 72, y + 94, 22, const Color(0xffa2aea4),
              width: 210);
        }
        final label =
            '${(page.index * 24 + i + 1).toString().padLeft(2, '0')}  ${cell.item.files.isEmpty ? '照片' : cell.item.files.first}';
        text(label, x, y + 228, 17, const Color(0xffe5dfd0), width: 324);
      }
      text('配方与原片独立保存 · 印样仅供浏览', 48, page.height - 48, 16,
          const Color(0xffa2aea4));
      final picture = recorder.endRecording();
      late ui.Image rendered;
      try {
        rendered = await picture.toImage(ContactSheetPage.width, page.height);
      } finally {
        picture.dispose();
      }
      try {
        final data =
            await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) throw StateError('无法生成印样像素');
        return ContactSheetRaster(
            PreviewImage(
                width: rendered.width,
                height: rendered.height,
                rgba: data.buffer
                    .asUint8List(data.offsetInBytes, data.lengthInBytes)),
            missingCount: missing);
      } finally {
        rendered.dispose();
      }
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }
}
