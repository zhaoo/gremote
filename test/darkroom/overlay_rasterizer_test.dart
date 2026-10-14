import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/frame/frame_layout.dart';
import 'package:gremote/darkroom/frame/overlay_rasterizer.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/imaging/imaging_engine.dart';

const content = FrameContent(
  model: 'RICOH GR III',
  params: '28mm f/2.8 1/250s ISO200',
  date: '2026.10.10',
);

bool hasOpaquePixels(ExportOverlay overlay) {
  for (var i = 3; i < overlay.rgba.length; i += 4) {
    if (overlay.rgba[i] > 0) return true;
  }
  return false;
}

void main() {
  testWidgets('rasterizes the classic info bar at output size', (tester) async {
    final layout = computeFrameLayout(
        photoWidth: 600,
        photoHeight: 400,
        style: FrameStyle.classic,
        ratio: FrameRatio.original,
        content: content);
    final overlays = await tester
        .runAsync(() => const OverlayRasterizer().rasterize(layout));
    expect(overlays, hasLength(1));
    final info = overlays!.single;
    expect(info.x, layout.overlays.single.rect.x);
    expect(info.width, 600);
    expect(info.rgba.length, info.width * info.height * 4);
    expect(hasOpaquePixels(info), isTrue);
  });

  testWidgets('skips regions whose fields are all hidden', (tester) async {
    final layout = computeFrameLayout(
        photoWidth: 600,
        photoHeight: 400,
        style: FrameStyle.classic,
        ratio: FrameRatio.original,
        content: const FrameContent());
    final overlays = await tester
        .runAsync(() => const OverlayRasterizer().rasterize(layout));
    expect(overlays, isEmpty);
  });

  testWidgets('paints sprockets and the caption accent within their regions',
      (tester) async {
    final contact = computeFrameLayout(
        photoWidth: 600,
        photoHeight: 400,
        style: FrameStyle.contact,
        ratio: FrameRatio.square,
        content: const FrameContent());
    final strips = await tester
        .runAsync(() => const OverlayRasterizer().rasterize(contact));
    expect(strips, hasLength(2));
    expect(strips!.every(hasOpaquePixels), isTrue);

    final street = computeFrameLayout(
        photoWidth: 600,
        photoHeight: 400,
        style: FrameStyle.street,
        ratio: FrameRatio.original,
        content: content);
    final lines = await tester
        .runAsync(() => const OverlayRasterizer().rasterize(street));
    expect(lines, hasLength(1));
    expect(hasOpaquePixels(lines!.single), isTrue);
    final accent =
        street.overlays.single.elements.whereType<FrameRect>().single;
    final offset = (accent.rect.y * lines.single.width + accent.rect.x) * 4;
    expect(lines.single.rgba.sublist(offset, offset + 4), [188, 165, 127, 255]);
  });
}
