import 'dart:convert';
import 'dart:async';
import 'package:gremote/darkroom/export/export_work_gate.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:gremote/film/export/canvas_contact_sheet_rasterizer.dart';
import 'package:gremote/film/export/ffi_generated_jpeg_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/export/contact_sheet_layout.dart';
import 'package:gremote/film/export/contact_sheet_exporter.dart';
import 'package:gremote/film/model/camera_photo_identity.dart';
import 'package:gremote/film/model/film_roll.dart';
import 'package:gremote/imaging/imaging_engine.dart';
import '../support/fake_media_gateway.dart';

class PageRasterizer implements ContactSheetRasterizer {
  final pages = <List<ContactSheetCell>>[];
  @override
  Future<ContactSheetRaster> rasterize(FilmRoll roll, ContactSheetPage page,
      List<ContactSheetCell> cells) async {
    pages.add(cells);
    return ContactSheetRaster(
        PreviewImage(width: 2, height: 2, rgba: Uint8List(16)),
        missingCount: cells.where((c) => c.thumbnail == null).length);
  }
}

class FileEncoder implements GeneratedJpegEncoder {
  @override
  Future<void> encode(PreviewImage image, String path,
      {ImagingCancelToken? cancel}) async {
    await File(path).writeAsBytes([1, 2, 3]);
  }
}

class FirstPublishFails extends FakeMediaGateway {
  int attempts = 0;
  @override
  Future<String> publishGenerated(
      {required String tempPath,
      required String displayName,
      required int width,
      required int height}) async {
    attempts++;
    if (attempts == 1) throw const FileSystemException('No space');
    return 'content://generated/$attempts';
  }
}

class ReusedPhotoId extends FakeMediaGateway {
  int thumbnailCalls = 0;
  @override
  Future<Uint8List?> thumbnail(int id, int edge) async {
    thumbnailCalls++;
    return Uint8List.fromList([1, 2, 3]);
  }
}

class StalledMedia extends FakeMediaGateway {
  final started = Completer<void>();
  @override
  Future<Uint8List?> thumbnail(int id, int edge) {
    started.complete();
    return Completer<Uint8List?>().future;
  }
}

void main() {
  final catalog = FilmCatalog.fromJson(
          jsonDecode(File('assets/films/catalog.json').readAsStringSync())
              as Map<String, dynamic>),
      recipe = FilmCatalog.fromJson(
              jsonDecode(File('assets/films/catalog.json').readAsStringSync())
                  as Map<String, dynamic>)
          .recipe(33);
  List<RollItem> items(int count) => [
        for (var i = 0; i < count; i++)
          RollItem(
              id: 'p$i',
              rollId: 'r1',
              identity: CameraPhotoIdentity(
                  instanceId: 'phone',
                  storageId: 'local',
                  storageEpoch: 'e1',
                  dir: 'images',
                  baseName: 'P$i',
                  contentHash: '$i'),
              recipe: recipe,
              files: ['P$i.JPG'],
              confidence: RecipeConfidence.userAssigned,
              createdAt: DateTime(2026),
              mediaId: i,
              selected: i.isEven)
      ];
  final roll = FilmRoll(
      id: 'r1',
      name: '雨后散步',
      targetCount: 36,
      recipeFingerprint: catalog.recipe(33).fingerprint,
      status: FilmRollStatus.closed,
      createdAt: DateTime(2026));
  test('cancel stalled media read releases gate for darkroom export', () async {
    final gateway = StalledMedia(), cancel = ImagingCancelToken();
    addTearDown(cancel.dispose);
    final result = ContactSheetExporter(
            gateway: gateway,
            rasterizer: PageRasterizer(),
            encoder: FileEncoder())
        .export(roll, items(1), cancel: cancel)
        .toList();
    await gateway.started.future;
    cancel.cancel();
    expect(
        (await result.timeout(const Duration(milliseconds: 150))).last.status,
        ContactSheetStatus.cancelled);
    final release = await ExportWorkGate.acquire()
        .timeout(const Duration(milliseconds: 150));
    release();
    expect(gateway.generated, isEmpty);
  });
  test('contact sheet paginates and retains missing cells without recoloring',
      () async {
    final pages = ContactSheetLayout.pages(items(25));
    expect(pages.map((p) => p.items.length), [24, 1]);
    final dir = Directory.systemTemp.createTempSync('contact-sheet-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final rasterizer = PageRasterizer(),
        gateway = FakeMediaGateway(),
        cancel = ImagingCancelToken();
    addTearDown(cancel.dispose);
    final exporter = ContactSheetExporter(
        gateway: gateway,
        rasterizer: rasterizer,
        encoder: FileEncoder(),
        tempDir: () async => dir);
    final result =
        await exporter.export(roll, items(25), cancel: cancel).toList();
    expect(
        result.where((p) => p.status == ContactSheetStatus.done), hasLength(2));
    expect(result.last.missingCount, 1);
    expect(rasterizer.pages.first, hasLength(24));
    expect(rasterizer.pages.first.every((p) => p.thumbnail == null), isTrue);
    expect(gateway.generated, hasLength(2));
    expect(await dir.list().toList(), isEmpty);
  });
  test(
      'publish failure does not stop later page and cancellation avoids publishing',
      () async {
    final dir = Directory.systemTemp.createTempSync('contact-sheet-failure');
    addTearDown(() => dir.deleteSync(recursive: true));
    final gateway = FirstPublishFails(), cancel = ImagingCancelToken();
    addTearDown(cancel.dispose);
    final exporter = ContactSheetExporter(
        gateway: gateway,
        rasterizer: PageRasterizer(),
        encoder: FileEncoder(),
        tempDir: () async => dir);
    final result =
        await exporter.export(roll, items(25), cancel: cancel).toList();
    expect(result.any((p) => p.status == ContactSheetStatus.failed), isTrue);
    expect(result.last.status, ContactSheetStatus.done);
    expect(await dir.list().toList(), isEmpty);
    final retried = await exporter
        .export(roll, items(25), cancel: cancel, pageIndices: {0}).toList();
    expect(retried.last.status, ContactSheetStatus.done);
    expect(
        retried
            .where((p) => p.status == ContactSheetStatus.done)
            .single
            .pageIndex,
        0);
    expect(gateway.attempts, 3);
    cancel.cancel();
    final stopped =
        await exporter.export(roll, items(1), cancel: cancel).toList();
    expect(stopped.last.status, ContactSheetStatus.cancelled);
    expect(gateway.attempts, 3);
  });
  testWidgets(
      'real canvas and native encoder produce readable contact sheet JPEG',
      (tester) async {
    await tester.runAsync(() async {
      final page = ContactSheetLayout.pages(items(1)).single;
      final raster = await const CanvasContactSheetRasterizer()
          .rasterize(roll, page, [ContactSheetCell(page.items.single, null)]);
      final image = raster.image;
      expect(raster.missingCount, 1);
      expect(image.width, 1440);
      expect(image.height, page.height);
      final dir = await Directory.systemTemp.createTemp('contact-real-');
      try {
        final path = '${dir.path}/page.jpg';
        await const FfiGeneratedJpegEncoder(
                libraryPath:
                    'native/imaging/build/host/libgremote_imaging.dylib')
            .encode(image, path);
        final codec =
            await ui.instantiateImageCodec(await File(path).readAsBytes());
        final decoded = (await codec.getNextFrame()).image;
        expect(decoded.width, 1440);
        expect(decoded.height, 508);
        final pixels = await decoded.toByteData();
        // Placeholder panel differs from the surrounding background.
        expect(pixels!.getUint8((180 * 1440 + 60) * 4),
            greaterThan(pixels.getUint8(0)));
        decoded.dispose();
        codec.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
  test(
      'contact export waits for active darkroom export and releases on cancellation',
      () async {
    final release = await ExportWorkGate.acquire();
    final cancel = ImagingCancelToken();
    addTearDown(cancel.dispose);
    final gateway = FakeMediaGateway();
    final exporter = ContactSheetExporter(
        gateway: gateway, rasterizer: PageRasterizer(), encoder: FileEncoder());
    var finished = false;
    final pending =
        exporter.export(roll, items(1), cancel: cancel).toList().then((r) {
      finished = true;
      return r;
    });
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(gateway.generated, isEmpty);
    cancel.cancel();
    release();
    expect((await pending).single.status, ContactSheetStatus.cancelled);
    final next = await ExportWorkGate.acquire();
    next();
  });
  test('reused local media ID never exports a different original', () async {
    final old = items(1).single;
    final local = RollItem(
        id: old.id,
        rollId: old.rollId,
        identity: CameraPhotoIdentity(
            instanceId: 'local-photo',
            storageId: 'local',
            storageEpoch: 'sha256-v1',
            dir: 'images',
            baseName: 'old',
            contentHash: 'a' * 64),
        recipe: old.recipe,
        files: old.files,
        confidence: old.confidence,
        createdAt: old.createdAt,
        mediaId: 7);
    final gateway = ReusedPhotoId()..contentHashes[7] = 'b' * 64;
    final rasterizer = PageRasterizer(), cancel = ImagingCancelToken();
    final dir = Directory.systemTemp.createTempSync('contact-id-reuse-');
    addTearDown(cancel.dispose);
    addTearDown(() => dir.deleteSync(recursive: true));
    final result = await ContactSheetExporter(
            gateway: gateway,
            rasterizer: rasterizer,
            encoder: FileEncoder(),
            tempDir: () async => dir)
        .export(roll, [local], cancel: cancel)
        .toList();
    expect(result.last.missingCount, 1);
    expect(gateway.thumbnailCalls, 0);
    expect(rasterizer.pages.single.single.thumbnail, isNull);
  });

  testWidgets('corrupt thumbnail placeholder counts as a missing image',
      (tester) async {
    await tester.runAsync(() async {
      final gateway = ReusedPhotoId(), cancel = ImagingCancelToken();
      final dir = await Directory.systemTemp.createTemp('contact-corrupt-');
      try {
        final result = await ContactSheetExporter(
                gateway: gateway,
                rasterizer: const CanvasContactSheetRasterizer(),
                encoder: FileEncoder(),
                tempDir: () async => dir)
            .export(roll, items(1), cancel: cancel)
            .toList();
        expect(result.last.status, ContactSheetStatus.done);
        expect(result.last.missingCount, 1);
      } finally {
        cancel.dispose();
        await dir.delete(recursive: true);
      }
    });
  });
}
