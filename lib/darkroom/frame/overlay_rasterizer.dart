import 'dart:ui' as ui;

import '../../imaging/imaging_engine.dart';
import 'frame_layout.dart';
import 'frame_painter.dart';

/// Renders each non-empty overlay region at output resolution as straight
/// RGBA for the native compositor.
class OverlayRasterizer {
  const OverlayRasterizer();

  Future<List<ExportOverlay>> rasterize(FrameLayout layout) async {
    final result = <ExportOverlay>[];
    for (final overlay in layout.overlays) {
      if (overlay.elements.isEmpty) continue;
      final rect = overlay.rect;
      final recorder = ui.PictureRecorder();
      FramePainter.paintOverlay(ui.Canvas(recorder), overlay);
      final picture = recorder.endRecording();
      final image = await picture.toImage(rect.width, rect.height);
      picture.dispose();
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      image.dispose();
      if (data == null) throw StateError('overlay rasterization failed');
      result.add(ExportOverlay(
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ));
    }
    return result;
  }
}
