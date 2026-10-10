import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/export/export_service.dart';
import 'package:gremote/darkroom/frame/frame_layout.dart';
import 'package:gremote/darkroom/frame/overlay_rasterizer.dart';
import 'package:gremote/darkroom/lut/lut_library.dart';
import 'package:gremote/darkroom/model/photo_meta.dart';
import 'package:gremote/darkroom/store/darkroom_store.dart';
import 'package:gremote/imaging/imaging_engine.dart';
import 'package:gremote/media/local/media_gateway.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_imaging_engine.dart';
import 'fake_media_gateway.dart';

LocalMediaEntry mediaEntry(int id) => LocalMediaEntry(
      id: id,
      uri: 'content://media/external/images/media/$id',
      displayName: 'R00$id.JPG',
      dateModified: 100,
      dateTaken: id * 1000,
      width: 6000,
      height: 4000,
    );

PhotoMeta grMeta({int orientation = 1}) => PhotoMeta(
      width: 6000,
      height: 4000,
      orientation: orientation,
      make: 'RICOH IMAGING COMPANY, LTD.',
      model: 'RICOH GR III',
      fNumber: 2.8,
      exposureTime: 1 / 250,
      iso: 200,
      focal35: 28,
      takenAt: '2026:10:10 08:30:00',
    );

/// Skips `dart:ui` rasterization, which never completes under fake async.
class NoOverlayRasterizer implements OverlayRasterizer {
  @override
  Future<List<ExportOverlay>> rasterize(FrameLayout layout) async => const [];
}

/// In-memory database plus fakes for every darkroom platform boundary.
class TestDarkroom {
  TestDarkroom._(this.db, this.gateway, this.engine, this.dir);

  static Future<TestDarkroom> create({FakeMediaGateway? gateway}) async {
    sqfliteFfiInit();
    // The no-isolate factory completes inside widget tests' fake async zone.
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    return TestDarkroom._(db, gateway ?? FakeMediaGateway(),
        FakeImagingEngine(), Directory.systemTemp.createTempSync('gremote-test'));
  }

  final Database db;
  final FakeMediaGateway gateway;
  final FakeImagingEngine engine;
  final Directory dir;

  DarkroomStore get store => DarkroomStore(db);

  List<Override> get overrides => [
        databaseProvider.overrideWithValue(db),
        mediaGatewayProvider.overrideWithValue(gateway),
        imagingEngineProvider.overrideWithValue(engine),
        lutLibraryProvider.overrideWith((ref) => LutLibrary(
              store: ref.watch(darkroomStoreProvider),
              engine: engine,
              dataDir: () async => dir,
            )),
        exportServiceProvider.overrideWith((ref) => ExportService(
              engine: engine,
              gateway: gateway,
              rasterizer: NoOverlayRasterizer(),
              loadCube: ref.watch(lutLibraryProvider).load,
              tempDir: () async => dir,
            )),
      ];

  Future<void> close() async {
    await db.close();
    dir.deleteSync(recursive: true);
  }
}
