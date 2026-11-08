import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/companion/companion_sync_controller.dart';
import 'package:gremote/camera/companion/sync_state.dart';
import 'package:gremote/features/camera/camera_availability.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:gremote/film/store/sync_repository.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'camera_profiles_sync_test.dart' show ProfileCompanion;

// Identity from the user's m10v-gr3-gremote firmware/service receipts.
const _catalogHash =
    'dec78e808816dd21e7e6225a7a3c539699bd0572bb018b719e7fcc5c328be696';
const _rendererHash =
    'db7fdff7b13e23447f4a58c561b92813319acf249b8922f75b4ffdad3bb74f30';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('public GR III package reads ten slots and explicitly installs a film',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final catalogs = await container.read(bundledCameraCatalogsProvider.future);
    final public = catalogs.singleWhere((c) => c.hash == _catalogHash);
    expect(public.rendererHash, _rendererHash);
    // This service's generated wire contract only accepts IDs through 326,
    // even though its raw display catalog already includes 327 (Marlboro).
    expect(public.contract['maximumFilmId'], 326);
    expect(public.entries.map((e) => e.id), isNot(contains(327)));
    expect(() => public.recipe(327), throwsFormatException);
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final api = ProfileCompanion(public);
    final sync = CompanionSyncController(
        api: api,
        repository: SyncRepository(db),
        catalogHash: catalogs.first.hash,
        rendererHash: catalogs.first.rendererHash,
        cameraCatalog: catalogs.first,
        resolveCameraCatalog: (caps) => catalogs
            .where((c) =>
                c.hash == caps.catalogHash &&
                c.rendererHash == caps.rendererHash)
            .firstOrNull,
        wait: () async {});
    addTearDown(sync.dispose);
    await sync.refresh();
    final available = CameraAvailability.fromState(
        connected: true, paired: true, sync: sync.state);
    expect(available.canReadFilms, isTrue);
    expect(available.canInstallFilms, isTrue);
    expect(available.snapshot!.slots, hasLength(10));
    expect(sync.cameraCatalog!.hash, _catalogHash);
    expect(api.operations, isEmpty);
    await sync.prepareLoad(
        slot: 0,
        recipe: public.recipe(33, parameters: {'grain': 2}),
        activate: true);
    expect(api.operations, isEmpty);
    await sync.confirm();
    expect(sync.state.operationStatus, SyncOperationStatus.synced);
    expect(sync.state.snapshot!.recipeAt(0).filmId, 33);
    expect(sync.state.snapshot!.recipeAt(0).parameters['grain'], 2);
    expect(sync.state.snapshot!.activeSlot, 0);
    expect(api.operations.first['catalogHash'], _catalogHash);
    expect(api.operations.first['rendererHash'], _rendererHash);
    expect(resolveCameraFilmProfile(_catalogHash, catalogs.first.rendererHash),
        isNull);
    expect(
        resolveCameraFilmProfile(catalogs.first.hash, _rendererHash), isNull);
  });
}
