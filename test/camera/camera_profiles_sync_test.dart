import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/companion/companion_client.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'package:gremote/camera/companion/companion_sync_controller.dart';
import 'package:gremote/camera/companion/sync_state.dart';
import 'package:gremote/film/store/sync_repository.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'camera_profiles_test.dart' show oldCatalog, newCatalog;
import 'camera_film_contract_test.dart'
    show cameraStateFixture, cameraCapabilitiesFixture;
import 'companion_sync_controller_test.dart' show FakeCompanion;

class ProfileCompanion extends FakeCompanion {
  ProfileCompanion(this.catalog) {
    caps = {
      ...cameraCapabilitiesFixture(),
      'catalogHash': catalog.hash,
      'rendererHash': catalog.rendererHash,
      'parameters': catalog.contract['parameters']
    };
    current = Map<String, Object?>.from(cameraStateFixture()['config'] as Map);
  }
  final CameraFilmCatalog catalog;
  bool authenticated = false, fresh = true;
  @override
  String? get bootId => authenticated ? boot : null;
  @override
  void invalidate() {
    authenticated = false;
  }

  @override
  Future<CompanionCapabilities> capabilities() async {
    authenticated = true;
    return CompanionCapabilities.fromJson(caps, contract: catalog.contract);
  }

  @override
  CompanionSnapshot snapshot() => CompanionSnapshot.fromJson({
        ...cameraStateFixture(),
        'catalogHash': caps['catalogHash'],
        'rendererHash': caps['rendererHash'],
        'config': current,
        'revision': sequence.toRadixString(16).padLeft(64, '0'),
        'configHash': sequence.toRadixString(16).padLeft(64, '0'),
        'fresh': fresh,
        'activeSlot': active
      }, contract: catalog.contract);
  @override
  CompanionOperationReceipt receipt(
          Map<String, Object?> value, String status) =>
      CompanionOperationReceipt.fromJson({
        'requestId': value['requestId'],
        'bootId': boot,
        'status': status,
        if (status == 'committed') 'snapshot': snapshot().wire
      }, contract: catalog.contract);
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late SyncRepository repository;
  CompanionSyncController? controller;
  setUp(() async {
    db = await GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repository = SyncRepository(db);
  });
  tearDown(() async {
    controller?.dispose();
    controller = null;
    await db.close();
  });
  CompanionSyncController make(ProfileCompanion api) {
    final profiles = [newCatalog(), oldCatalog()];
    return controller = CompanionSyncController(
        api: api,
        repository: repository,
        catalogHash: profiles.first.hash,
        rendererHash: profiles.first.rendererHash,
        cameraCatalog: profiles.first,
        resolveCameraCatalog: (caps) {
          for (final profile in profiles) {
            if (profile.hash == caps.catalogHash &&
                profile.rendererHash == caps.rendererHash) return profile;
          }
          return null;
        },
        wait: () async {});
  }

  for (final version in ['old', 'current']) {
    test(
        '$version authenticated profile negotiates read, prepare and explicit load',
        () async {
      final catalog = version == 'old' ? oldCatalog() : newCatalog(),
          api =
              ProfileCompanion(version == 'old' ? oldCatalog() : newCatalog());
      final sync = make(api);
      await sync.refresh();
      expect(sync.state.readOnly, false);
      expect(sync.cameraCatalog!.hash, catalog.hash);
      expect(api.operations, isEmpty);
      final recipe = sync.state.snapshot!.recipeAt(0);
      await repository.saveCameraRecipe(recipe as CameraFilmRecipe);
      expect((await repository.cameraRecipes()).single.rendererHash,
          catalog.rendererHash);
      await sync.prepareLoad(
          slot: 0, recipe: catalog.recipe(33), activate: false);
      expect(api.operations, isEmpty);
      await sync.confirm();
      expect(sync.state.operationStatus, SyncOperationStatus.synced);
      expect(api.operations.single['rendererHash'], catalog.rendererHash);
    });
  }
  test('old profile refuses newest film and refuses cross-profile recipes',
      () async {
    final api = ProfileCompanion(oldCatalog());
    final sync = make(api);
    await sync.refresh();
    await expectLater(
        sync.prepareLoad(
            slot: 0, recipe: newCatalog().recipe(326), activate: false),
        throwsFormatException);
    await expectLater(
        sync.prepareLoad(
            slot: 0, recipe: newCatalog().recipe(33), activate: false),
        throwsFormatException);
    expect(api.operations, isEmpty);
  });
  test(
      'unknown authenticated pair remains read only with update hint and no POST',
      () async {
    final api = ProfileCompanion(oldCatalog())
      ..caps['rendererHash'] = 'ab' * 32;
    final sync = make(api);
    await sync.refresh();
    expect(sync.state.readOnly, true);
    expect(sync.state.message, contains('更新'));
    await expectLater(
        sync.prepareLoad(
            slot: 0, recipe: oldCatalog().recipe(33), activate: false),
        throwsA(isA<CompanionException>()));
    expect(api.operations, isEmpty);
  });
  test('disconnect and stale state cannot confirm a prepared load', () async {
    final api = ProfileCompanion(oldCatalog());
    final sync = make(api);
    await sync.prepareLoad(
        slot: 0, recipe: oldCatalog().recipe(33), activate: false);
    sync.disconnected();
    await sync.confirm();
    expect(api.operations, isEmpty);
    final actual = sync.api as ProfileCompanion;
    actual.fresh = false;
    await sync.refresh();
    await sync.confirm();
    expect(actual.operations, isEmpty);
    expect(sync.state.readOnly, true);
  });
  test(
      'profile switch clears the prepared draft without replaying an old operation',
      () async {
    final api = ProfileCompanion(oldCatalog()),
        sync = make(ProfileCompanion(oldCatalog()));
    final actual = sync.api as ProfileCompanion;
    await sync.prepareLoad(
        slot: 0, recipe: oldCatalog().recipe(33), activate: false);
    expect(sync.state.hasPreparedLoad, true);
    sync.disconnected();
    final next = newCatalog();
    actual.caps = {
      ...cameraCapabilitiesFixture(),
      'catalogHash': next.hash,
      'rendererHash': next.rendererHash
    };
    await sync.refresh();
    expect(sync.cameraCatalog!.hash, next.hash);
    expect(sync.state.hasPreparedLoad, false);
    await sync.confirm();
    expect(actual.operations, isEmpty);
    expect(api.operations, isEmpty);
  });
  test(
      'old pending operation survives App restart and is only reconciled explicitly',
      () async {
    final old = oldCatalog(), api = ProfileCompanion(oldCatalog());
    var sync = make(api);
    await sync.prepareLoad(slot: 0, recipe: old.recipe(33), activate: false);
    api.lost = true;
    await sync.confirm();
    expect(sync.state.operationStatus, SyncOperationStatus.unknown);
    expect(api.operations.length, 1);
    sync.dispose();
    controller = null;
    api.lost = false;
    sync = make(api);
    await sync.refresh();
    expect(sync.state.operationStatus, SyncOperationStatus.unknown);
    expect(api.operations.length, 1);
    await sync.reconcileUnknown();
    expect(sync.state.operationStatus, SyncOperationStatus.synced);
    expect(api.operations.length, 1);
  });
}
