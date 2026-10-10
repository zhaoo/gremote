import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/export/export_service.dart';
import 'package:gremote/darkroom/frame/frame_layout.dart';
import 'package:gremote/darkroom/frame/overlay_rasterizer.dart';
import 'package:gremote/darkroom/model/edit_document.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/darkroom/model/photo_meta.dart';
import 'package:gremote/imaging/imaging_engine.dart';
import 'package:gremote/imaging/imaging_exception.dart';
import 'package:gremote/media/local/local_media_repository.dart';
import 'package:gremote/media/local/media_gateway.dart';

import '../support/fake_imaging_engine.dart';
import '../support/fake_media_gateway.dart';

class FakeRasterizer implements OverlayRasterizer {
  Object? error;
  final layouts = <FrameLayout>[];

  @override
  Future<List<ExportOverlay>> rasterize(FrameLayout layout) async {
    layouts.add(layout);
    if (error != null) throw error!;
    return [
      for (final o in layout.overlays)
        if (o.elements.isNotEmpty)
          ExportOverlay(
              x: o.rect.x,
              y: o.rect.y,
              width: o.rect.width,
              height: o.rect.height,
              rgba: Uint8List(4)),
    ];
  }
}

LocalMediaItem photo(int id, {PhotoMeta? meta}) => LocalMediaItem(
      id: id,
      uri: 'content://media/$id',
      displayName: 'R00$id.JPG',
      dateModified: 1,
      meta: meta ??
          const PhotoMeta(
              width: 600,
              height: 400,
              orientation: 6,
              model: 'RICOH GR III',
              fNumber: 2.8),
    );

EditDocument doc(int id, [ExportRecipe recipe = const ExportRecipe()]) =>
    EditDocument(mediaId: id, recipe: recipe, updatedAt: DateTime(2026));

void main() {
  late Directory temp;
  late FakeImagingEngine engine;
  late FakeMediaGateway gateway;
  late FakeRasterizer rasterizer;
  late List<String> loadedLuts;
  late ExportService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gremote-export');
    engine = FakeImagingEngine();
    gateway = FakeMediaGateway();
    rasterizer = FakeRasterizer();
    loadedLuts = [];
    service = ExportService(
      engine: engine,
      gateway: gateway,
      rasterizer: rasterizer,
      loadCube: (id) async {
        loadedLuts.add(id);
        return Uint8List.fromList([1, 2, 3]);
      },
      tempDir: () async => temp,
      clock: () => DateTime(2026, 10, 10, 8, 5, 9),
    );
  });

  tearDown(() => temp.delete(recursive: true));

  test('names exports after the source and time', () {
    expect(exportFileName('R0001234.JPG', DateTime(2026, 10, 10, 8, 5, 9)),
        'gremote_R0001234_20261010-080509.jpg');
  });

  test('renders with fd, overlays and LUT, then publishes and cleans up',
      () async {
    final outcome = await service.export(
      photo(7),
      doc(
          7,
          const ExportRecipe(
              lutId: 'builtin:pale', strength: 0.6, keepGps: true)),
    );

    final job = engine.jobs.single;
    expect(job.fd, gateway.openedFds.single);
    expect(job.orientation, 6);
    expect(job.cube, [1, 2, 3]);
    expect(job.lutStrength, 0.6);
    expect(job.quality, 95);
    final layout = rasterizer.layouts.single;
    expect(job.canvasWidth, layout.canvasWidth);
    expect(job.photoWidth, 400, reason: 'orientation 6 swaps width/height');
    expect(job.photoHeight, 600);
    expect(job.overlays, hasLength(1));
    expect(p(job.outputPath).startsWith(temp.path), isTrue);
    expect(loadedLuts, ['builtin:pale']);

    final publish = gateway.publishes.single;
    expect(publish.tempPath, job.outputPath);
    expect(publish.sourceId, 7);
    expect(publish.keepGps, isTrue);
    expect(publish.displayName, 'gremote_R007_20261010-080509.jpg');
    expect((publish.width, publish.height),
        (layout.canvasWidth, layout.canvasHeight));
    expect(outcome.uri, startsWith('content://'));
    expect(File(job.outputPath).existsSync(), isFalse);
  });

  test('skips LUT loading without a LUT and honours the size preset', () async {
    await service.export(
        photo(1, meta: const PhotoMeta(width: 6000, height: 4000)),
        doc(1, const ExportRecipe(size: ExportSize.long1440)));
    expect(loadedLuts, isEmpty);
    expect(engine.jobs.single.cube, isNull);
    expect((engine.jobs.single.photoWidth, engine.jobs.single.photoHeight),
        (1440, 960));
  });

  test('native failure skips publishing and deletes the temp file', () async {
    engine.exportFailures[1] = ImagingErrorCode.encode;
    await expectLater(
      service.export(photo(1), doc(1)),
      throwsA(isA<ExportFailure>()
          .having((e) => e.stage, 'stage', ExportStage.encode)
          .having((e) => e.fileName, 'fileName', 'R001.JPG')
          .having((e) => e.code, 'code', 'encode')),
    );
    expect(gateway.publishes, isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test('rasterizer failure never opens a descriptor', () async {
    rasterizer.error = StateError('boom');
    await expectLater(
        service.export(photo(1), doc(1)),
        throwsA(isA<ExportFailure>()
            .having((e) => e.stage, 'stage', ExportStage.compose)));
    expect(gateway.openedFds, isEmpty);
  });

  test('publish failure reports the save stage with a next step', () async {
    gateway.publishError = const MediaException('storageFull', 'ENOSPC');
    await expectLater(
      service.export(photo(1), doc(1)),
      throwsA(isA<ExportFailure>()
          .having((e) => e.stage, 'stage', ExportStage.save)
          .having((e) => e.hint, 'hint', contains('存储'))),
    );
    expect(temp.listSync(), isEmpty);
  });

  test('cancellation surfaces as ExportCancelled', () async {
    final token = ImagingCancelToken()..cancel();
    addTearDown(token.dispose);
    await expectLater(service.export(photo(1), doc(1), cancel: token),
        throwsA(isA<ExportCancelled>()));
    expect(gateway.publishes, isEmpty);
  });

  test('missing EXIF fails in the read stage', () async {
    const item =
        LocalMediaItem(id: 3, uri: 'u', displayName: 'x.jpg', dateModified: 1);
    await expectLater(
        service.export(item, doc(3)),
        throwsA(isA<ExportFailure>()
            .having((e) => e.stage, 'stage', ExportStage.read)));
  });
}

String p(String path) => File(path).absolute.path;
