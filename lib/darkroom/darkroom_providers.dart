import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../imaging/ffi_imaging_engine.dart';
import '../imaging/imaging_engine.dart';
import '../media/local/local_media_repository.dart';
import '../media/local/media_gateway.dart';
import '../media/local/native_media_gateway.dart';
import 'export/export_service.dart';
import 'lut/lut_library.dart';
import 'store/darkroom_store.dart';

/// Opened in bootstrap and injected with `overrideWithValue`.
final databaseProvider = Provider<Database>(
    (ref) => throw UnimplementedError('databaseProvider must be overridden'));

final mediaGatewayProvider =
    Provider<MediaGateway>((ref) => NativeMediaGateway());

final imagingEngineProvider =
    Provider<ImagingEngine>((ref) => FfiImagingEngine());

final localMediaRepositoryProvider = Provider<LocalMediaRepository>((ref) =>
    LocalMediaRepository(
        ref.watch(databaseProvider), ref.watch(mediaGatewayProvider)));

final thumbnailProvider = FutureProvider.autoDispose.family<Uint8List?, int>(
    (ref, id) => ref.watch(mediaGatewayProvider).thumbnail(id, 256));

/// Bumped whenever edits, presets or LUTs change so overviews reload.
final darkroomRevisionProvider = StateProvider<int>((ref) => 0);

final darkroomStoreProvider = Provider<DarkroomStore>(
    (ref) => DarkroomStore(ref.watch(databaseProvider)));

final lutLibraryProvider = Provider<LutLibrary>((ref) => LutLibrary(
      store: ref.watch(darkroomStoreProvider),
      engine: ref.watch(imagingEngineProvider),
      dataDir: getApplicationSupportDirectory,
    ));

final exportServiceProvider = Provider<ExportService>((ref) => ExportService(
      engine: ref.watch(imagingEngineProvider),
      gateway: ref.watch(mediaGatewayProvider),
      loadCube: ref.watch(lutLibraryProvider).load,
      tempDir: getTemporaryDirectory,
    ));
