import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/frame/frame_layout.dart';
import 'package:gremote/darkroom/model/edit_document.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/darkroom/model/photo_meta.dart';

const content = FrameContent(
  model: 'RICOH GR III',
  params: '28mm f/2.8 1/250s ISO200',
  date: '2026.10.10',
  title: '雨后',
  location: '上海',
);

Iterable<FrameText> texts(FrameLayout layout) => layout.overlays
    .expand((overlay) => overlay.elements)
    .whereType<FrameText>();

bool contains(FrameLayout layout, PixelRect inner) =>
    inner.x >= 0 &&
    inner.y >= 0 &&
    inner.right <= layout.canvasWidth &&
    inner.bottom <= layout.canvasHeight;

void main() {
  group('ExportRecipe', () {
    test('defaults match the design', () {
      const recipe = ExportRecipe();
      expect(recipe.lutId, isNull);
      expect(recipe.strength, 1);
      expect(recipe.frame, FrameStyle.classic);
      expect(recipe.ratio, FrameRatio.original);
      expect(recipe.size, ExportSize.original);
      expect(recipe.quality, 95);
      expect(recipe.keepGps, isFalse);
    });

    test('round-trips JSON and ignores unknown or invalid values', () {
      const recipe = ExportRecipe(
        lutId: 'builtin:pale',
        strength: 0.6,
        frame: FrameStyle.contact,
        ratio: FrameRatio.portrait4x5,
        size: ExportSize.long1440,
        quality: 90,
        keepGps: true,
      );
      expect(ExportRecipe.fromJson(recipe.toJson()), recipe);
      final messy = ExportRecipe.fromJson(const {
        'strength': 7,
        'frame': 'nope',
        'quality': 42,
        'future': true,
      });
      expect(messy.strength, 1);
      expect(messy.frame, FrameStyle.classic);
      expect(messy.quality, 95);
    });
  });

  group('EditDocument', () {
    test('round-trips hidden fields and text', () {
      final doc = EditDocument(
        mediaId: 7,
        recipe: const ExportRecipe(frame: FrameStyle.street),
        title: 't',
        location: 'l',
        hidden: const {FrameField.iso, FrameField.date},
        updatedAt: DateTime.utc(2026, 10, 10),
      );
      final restored = EditDocument.fromJsonParts(
        mediaId: 7,
        recipeJson: doc.recipeJson,
        title: 't',
        location: 'l',
        hiddenJson: doc.hiddenJson,
        updatedAt: doc.updatedAt,
      );
      expect(restored.hidden, {FrameField.iso, FrameField.date});
      expect(restored.recipe.frame, FrameStyle.street);
    });
  });

  group('PhotoMeta', () {
    const meta = PhotoMeta(
      width: 6000,
      height: 4000,
      orientation: 6,
      model: 'RICOH GR III',
      fNumber: 2.8,
      exposureTime: 1 / 250,
      iso: 200,
      focal35: 28,
      focal: 18.3,
      takenAt: '2026:10:10 08:30:00',
    );

    test('formats exposure labels', () {
      expect(meta.shutterLabel, '1/250s');
      expect(meta.copyWith(exposureTime: 1.3).shutterLabel, '1.3s');
      expect(meta.copyWith(exposureTime: 2).shutterLabel, '2s');
      expect(meta.apertureLabel, 'f/2.8');
      expect(meta.copyWith(fNumber: 8).apertureLabel, 'f/8');
      expect(meta.isoLabel, 'ISO200');
      expect(meta.focalLabel, '28mm');
      expect(meta.dateLabel, '2026.10.10');
    });

    test('falls back to the real focal length and hides missing values', () {
      const bare = PhotoMeta(width: 10, height: 10, focal: 18.3);
      expect(bare.focalLabel, '18mm');
      expect(bare.apertureLabel, isNull);
      expect(bare.shutterLabel, isNull);
      expect(bare.dateLabel, isNull);
    });

    test('swaps dimensions for rotated orientations', () {
      expect(meta.orientedWidth, 4000);
      expect(meta.orientedHeight, 6000);
      expect(meta.copyWith(orientation: 3).orientedWidth, 6000);
    });

    test('builds frame content honouring hidden fields', () {
      final full = FrameContent.from(meta, title: '雨后', location: '');
      expect(full.params, '28mm f/2.8 1/250s ISO200');
      expect(full.location, isNull);
      final hidden = FrameContent.from(meta,
          title: '雨后',
          location: '上海',
          hidden: const {FrameField.model, FrameField.iso, FrameField.title});
      expect(hidden.model, isNull);
      expect(hidden.params, '28mm f/2.8 1/250s');
      expect(hidden.title, isNull);
      expect(hidden.location, '上海');
    });
  });

  group('photo scaling', () {
    test('only shrinks to the requested long edge', () {
      expect(scaledPhotoSize(6000, 4000, ExportSize.original), (6000, 4000));
      expect(scaledPhotoSize(4000, 6000, ExportSize.long1440), (960, 1440));
      expect(scaledPhotoSize(6000, 4000, ExportSize.long2560), (2560, 1707));
      expect(scaledPhotoSize(1200, 800, ExportSize.long1440), (1200, 800));
    });
  });

  group('FrameLayout', () {
    test('classic margins follow the long edge', () {
      final layout = computeFrameLayout(
          photoWidth: 6000,
          photoHeight: 4000,
          style: FrameStyle.classic,
          ratio: FrameRatio.original,
          content: content);
      expect(layout.photo, const PixelRect(210, 210, 6000, 4000));
      expect(layout.canvasWidth, 6420);
      expect(layout.canvasHeight, 210 + 4000 + 660);
      expect(layout.background, 0xFFFFFFFF);
      expect(
          texts(layout).map((t) => t.text),
          containsAll(
              ['RICOH GR III', '28mm f/2.8 1/250s ISO200', '2026.10.10']));
    });

    test('street style adds a hairline around the photo', () {
      final layout = computeFrameLayout(
          photoWidth: 4000,
          photoHeight: 6000,
          style: FrameStyle.street,
          ratio: FrameRatio.original,
          content: content);
      expect(layout.photo.x, 270);
      expect(layout.canvasHeight, 270 + 6000 + 720);
      final rects = layout.overlays
          .expand((o) => o.elements)
          .whereType<FrameRect>()
          .toList();
      expect(rects, hasLength(4));
    });

    test('contact sheet places sprocket strips above and below', () {
      final layout = computeFrameLayout(
          photoWidth: 6000,
          photoHeight: 4000,
          style: FrameStyle.contact,
          ratio: FrameRatio.original,
          content: content);
      expect(layout.photo, const PixelRect(180, 510, 6000, 4000));
      expect(layout.canvasHeight, 4000 + 2 * 510);
      expect(
          layout.overlays.expand((o) => o.elements).whereType<FrameSprockets>(),
          hasLength(2));
      expect(texts(layout).any((t) => t.text.contains('GRemote · RICOH GR III')),
          isTrue);
    });

    for (final style in FrameStyle.values) {
      for (final ratio in FrameRatio.values.where((r) => r.aspect != null)) {
        test('${style.name} ${ratio.name} pads to an exact ratio', () {
          final layout = computeFrameLayout(
              photoWidth: 6000,
              photoHeight: 4000,
              style: style,
              ratio: ratio,
              content: content);
          final (w, h) = ratio.aspect!;
          expect(layout.canvasWidth * h, layout.canvasHeight * w);
          expect(layout.photo.width, 6000);
          expect(layout.photo.height, 4000);
          expect(contains(layout, layout.photo), isTrue);
          for (final overlay in layout.overlays) {
            expect(contains(layout, overlay.rect), isTrue);
          }
        });
      }
    }

    test('hidden fields keep the info region without text', () {
      final layout = computeFrameLayout(
          photoWidth: 6000,
          photoHeight: 4000,
          style: FrameStyle.classic,
          ratio: FrameRatio.original,
          content: const FrameContent());
      expect(layout.canvasHeight, 210 + 4000 + 660);
      expect(texts(layout), isEmpty);
    });
  });
}
