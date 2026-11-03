import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/camera/companion/companion_sync_controller.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:gremote/film/store/sync_repository.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'camera_profiles_sync_test.dart' show ProfileCompanion;
import 'camera_profiles_test.dart' show oldCatalog, newCatalog;

void main() {
  sqfliteFfiInit();
  test(
      'UI catalog follows authenticated old profile while latest bundle stays current',
      () async {
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final current = newCatalog(),
        old = oldCatalog(),
        api = ProfileCompanion(old);
    final sync = CompanionSyncController(
        api: api,
        repository: SyncRepository(db),
        catalogHash: current.hash,
        rendererHash: current.rendererHash,
        cameraCatalog: current,
        resolveCameraCatalog: (caps) =>
            caps.catalogHash == old.hash ? old : current);
    addTearDown(sync.dispose);
    final container = ProviderContainer(overrides: [
      latestBundledCameraCatalogProvider.overrideWith((_) async => current),
      companionSyncControllerProvider.overrideWithValue(sync)
    ]);
    addTearDown(container.dispose);
    final subscription =
        container.listen(cameraFilmCatalogProvider, (_, __) {});
    addTearDown(subscription.close);
    expect((await container.read(cameraFilmCatalogProvider.future)).hash,
        current.hash);
    await sync.refresh();
    expect((await container.read(cameraFilmCatalogProvider.future)).hash,
        old.hash);
    expect(
        (await container.read(latestBundledCameraCatalogProvider.future)).hash,
        current.hash);
    expect(api.operations, isEmpty);
  });
}
