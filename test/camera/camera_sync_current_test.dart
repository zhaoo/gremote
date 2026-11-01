import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:gremote/film/store/sync_repository.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'package:gremote/camera/companion/companion_sync_controller.dart';
import 'package:gremote/camera/companion/generated_camera_contract.dart';
import 'package:gremote/camera/companion/sync_state.dart';
import 'companion_sync_controller_test.dart' show FakeCompanion;
import 'camera_film_contract_test.dart'
    show cameraCapabilitiesFixture, cameraStateFixture;

class CurrentCamera extends FakeCompanion {
  bool stale = false;
  CurrentCamera() {
    caps = cameraCapabilitiesFixture();
    current = Map<String, Object?>.from(cameraStateFixture()['config']);
    active = 9;
  }
  @override
  CompanionSnapshot snapshot() => CompanionSnapshot.fromJson({
        ...cameraStateFixture(),
        'config': current,
        'revision': sequence.toRadixString(16).padLeft(64, '0'),
        'configHash': sequence.toRadixString(16).padLeft(64, '0'),
        'activeSlot': active,
        'fresh': !stale
      }, contract: cameraContract);
  @override
  Future<CompanionCapabilities> capabilities() async =>
      CompanionCapabilities.fromJson(caps, contract: cameraContract);
  @override
  CompanionOperationReceipt receipt(
          Map<String, Object?> value, String status) =>
      CompanionOperationReceipt.fromJson({
        'requestId': value['requestId'],
        'bootId': boot,
        'status': status,
        if (status == 'committed') 'snapshot': snapshot().wire
      }, contract: cameraContract);
}

void main() {
  late Database db;
  late CurrentCamera api;
  late CameraFilmCatalog catalog;
  late CompanionSyncController sync;
  setUp(() async {
    sqfliteFfiInit();
    db = await GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    api = CurrentCamera();
    catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-catalog.json').readAsStringSync()));
    sync = CompanionSyncController(
        api: api,
        repository: SyncRepository(db),
        catalogHash: cameraCatalogHash,
        rendererHash: cameraRendererHash,
        cameraCatalog: catalog,
        wait: () async {});
  });
  tearDown(() async {
    sync.dispose();
    await db.close();
  });
  test(
      'current camera recipes persist separately from historical preview recipes',
      () async {
    final repository = SyncRepository(db);
    final r = catalog.recipe(321, parameters: {'haloProfile': 4});
    await repository.saveCameraRecipe(r);
    final restored = await repository.cameraRecipes();
    expect(restored.single.fingerprint, r.fingerprint);
    expect(await db.query('film_recipes'), isEmpty);
  });
  test(
      'existing film chooses its actual slot and retired parameters never enter patch',
      () async {
    final old = (api.current['slots'] as List)[9] as Map;
    (old['parameters'] as Map)['grainSize'] = 2;
    await sync.prepareLoad(
        slot: 0,
        recipe: catalog.recipe(321, parameters: {'grain': 2}),
        activate: true);
    expect(sync.preparedSlot, 9);
    expect(sync.state.readOnly, false);
    await sync.confirm();
    expect(sync.state.operationStatus, SyncOperationStatus.synced);
    expect(api.operations.length, 1);
    final patch = (api.operations.single['patch'] as List).single as Map;
    expect(patch['slot'], 9);
    expect(patch['grain'], 2);
    expect(patch.containsKey('grainSize'), false);
    expect(patch.containsKey('leakGain'), false);
    expect((api.current['slots'] as List)[9]['parameters']['grainSize'], 2);
    expect((api.current['slots'] as List)[0]['filmId'], 34);
  });
  test(
      'legacy local recipe migrates before installation and does not overwrite unrelated slot',
      () async {
    final legacy = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync()));
    final before = jsonEncode((api.current['slots'] as List)[9]);
    await sync.prepareLoad(
        slot: 7,
        recipe: legacy.recipe(33, parameters: {'haloGain': 2}),
        activate: false);
    expect(sync.preparedSlot, 7);
    await sync.confirm();
    expect((api.operations.single['patch'] as List).single['haloProfile'], 4);
    expect(jsonEncode((api.current['slots'] as List)[9]), before);
  });
  test('empty target beyond first empty prepares contiguous insertion',
      () async {
    for (var i = 5; i < 10; i++) {
      (api.current['slots'] as List)[i] = {
        'filmId': 0,
        'customHash': null,
        'parameters': {
          'grainSize': 0,
          'leakGain': 0,
          'leakPosition': 0,
          'leakSpread': 0,
          'leakVariation': 0
        }
      };
    }
    api.active = 0;
    await sync.prepareLoad(
        slot: 9, recipe: catalog.recipe(321), activate: false);
    expect(sync.preparedSlot, 5);
    expect(api.operations, isEmpty);
    await sync.confirm();
    expect(sync.state.operationStatus, SyncOperationStatus.synced);
  });
  test('confirmation refuses a snapshot that became stale', () async {
    await sync.prepareLoad(
        slot: 0,
        recipe: catalog.recipe(321, parameters: {'grain': 2}),
        activate: false);
    api.stale = true;
    await sync.confirm();
    expect(api.operations, isEmpty);
    expect(sync.state.readOnly, true);
  });
  test('old five-slot saved baseline cannot make current camera unwritable',
      () async {
    final old = cameraStateFixture()..['schemaVersion'] = 1;
    old['config']['slots'] = (old['config']['slots'] as List).take(5).toList();
    old['activeSlot'] = 0;
    await SyncRepository(db)
        .saveBaseline(api.caps['instanceId'] as String, old);
    await sync.refresh();
    expect(sync.state.readOnly, false);
    expect(sync.state.snapshot!.slots.length, 10);
  });
}
