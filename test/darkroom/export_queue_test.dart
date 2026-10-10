import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/export/export_queue.dart';
import 'package:gremote/darkroom/export/export_service.dart';
import 'package:gremote/darkroom/frame/frame_layout.dart';
import 'package:gremote/darkroom/frame/overlay_rasterizer.dart';
import 'package:gremote/darkroom/model/edit_document.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/darkroom/model/photo_meta.dart';
import 'package:gremote/darkroom/store/darkroom_store.dart';
import 'package:gremote/imaging/imaging_engine.dart';
import 'package:gremote/imaging/imaging_exception.dart';
import 'package:gremote/media/local/local_media_repository.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_imaging_engine.dart';
import '../support/fake_media_gateway.dart';

class _NoOverlays implements OverlayRasterizer {
  @override
  Future<List<ExportOverlay>> rasterize(FrameLayout layout) async => const [];
}

LocalMediaItem photo(int id) => LocalMediaItem(
      id: id,
      uri: 'content://media/$id',
      displayName: 'R00$id.JPG',
      dateModified: 1,
      meta: const PhotoMeta(width: 60, height: 40),
    );

void main() {
  sqfliteFfiInit();
  late Database db;
  late Directory temp;
  late FakeImagingEngine engine;
  late ProviderContainer container;

  ExportQueueController queue() => container.read(exportQueueProvider.notifier);
  List<ExportItemStatus> statuses() =>
      [for (final i in container.read(exportQueueProvider).items) i.status];

  setUp(() async {
    db = await GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    temp = await Directory.systemTemp.createTemp('gremote-queue');
    engine = FakeImagingEngine();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      exportServiceProvider.overrideWithValue(ExportService(
        engine: engine,
        gateway: FakeMediaGateway(),
        rasterizer: _NoOverlays(),
        loadCube: (_) async => Uint8List(0),
        tempDir: () async => temp,
      )),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  test('a failure does not stop the rest of the batch', () async {
    engine.exportFailures[2] = ImagingErrorCode.decode;
    await queue().start([photo(1), photo(2), photo(3)], const ExportRecipe());
    final state = container.read(exportQueueProvider);
    expect(statuses(), [
      ExportItemStatus.done,
      ExportItemStatus.failed,
      ExportItemStatus.done,
    ]);
    expect(state.running, isFalse);
    expect(state.count(ExportItemStatus.done), 2);
    expect(state.count(ExportItemStatus.failed), 1);
    expect(state.items[1].failure?.stage, ExportStage.read);
  });

  test('applies the batch recipe but keeps per-photo captions', () async {
    await DarkroomStore(db).saveEdit(
        EditDocument(mediaId: 2, title: '海边', updatedAt: DateTime(2026)));
    const recipe = ExportRecipe(frame: FrameStyle.contact, quality: 90);
    await queue().start([photo(1), photo(2)], recipe);
    final items = container.read(exportQueueProvider).items;
    expect(items.every((i) => i.doc.recipe == recipe), isTrue);
    expect(items[1].doc.title, '海边');
    expect(engine.jobs.map((j) => j.quality), [90, 90]);
  });

  test('startEach applies a different recipe to each photo', () async {
    const first = ExportRecipe(frame: FrameStyle.street, quality: 81);
    const second = ExportRecipe(frame: FrameStyle.contact, quality: 92);

    await queue().startEach([(photo(1), first), (photo(2), second)]);

    final items = container.read(exportQueueProvider).items;
    expect(items[0].doc.recipe, first);
    expect(items[1].doc.recipe, second);
    expect(engine.jobs.map((job) => job.quality), [81, 92]);
  });

  test('cancel stops the current photo and skips the rest', () async {
    engine.onExport = (_) {
      if (engine.jobs.length == 2) queue().cancel();
    };
    await queue().start([photo(1), photo(2), photo(3)], const ExportRecipe());
    expect(statuses(), [
      ExportItemStatus.done,
      ExportItemStatus.cancelled,
      ExportItemStatus.cancelled,
    ]);
    expect(engine.jobs, hasLength(2));
  });

  test('retry reruns failed items only', () async {
    engine.exportFailures[2] = ImagingErrorCode.decode;
    await queue().start([photo(1), photo(2), photo(3)], const ExportRecipe());
    engine.exportFailures.clear();
    await queue().retryFailed();
    expect(statuses(), everyElement(ExportItemStatus.done));
    expect(engine.jobs, hasLength(4));
    expect(engine.jobs.last.outputPath, contains('export-2-'));
  });
}
