import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/model/camera_photo_identity.dart';
import 'package:gremote/film/model/film_roll.dart';
import 'package:gremote/film/store/film_repository.dart';
import 'package:gremote/film/store/sync_repository.dart';

void main() {
  late Database db;
  late FilmRepository repo;
  late FilmCatalog catalog;
  setUp(() async {
    sqfliteFfiInit();
    db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    repo = FilmRepository(db);
    catalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync())
            as Map<String, dynamic>);
  });
  tearDown(() async => db.close());
  CameraPhotoIdentity identity(
          {String camera = 'camera-a', String epoch = 'card-1'}) =>
      CameraPhotoIdentity(
          instanceId: camera,
          storageId: 'sd',
          storageEpoch: epoch,
          dir: '100RICOH',
          baseName: 'R0000001',
          captureId: 'capture-1');
  test('open roll is unique even when callers race', () async {
    final outcomes = await Future.wait([
      for (var i = 0; i < 2; i++)
        repo
            .createRoll(name: '散步', targetCount: 36, recipe: catalog.recipe(33))
            .then((_) => true, onError: (_) => false)
    ]);
    expect(outcomes.where((v) => v), hasLength(1));
    expect(await repo.rolls(), hasLength(1));
  });
  test('late RAW merges while camera and card identities remain distinct',
      () async {
    final roll = await repo.createRoll(
        name: '雨后', targetCount: 24, recipe: catalog.recipe(33));
    for (final files in [
      ['R0000001.JPG'],
      ['R0000001.DNG']
    ]) {
      await repo.addConfirmedPhoto(
          rollId: roll.id,
          identity: identity(),
          recipe: catalog.recipe(33),
          files: files,
          confidence: RecipeConfidence.cameraConfirmed);
    }
    expect((await repo.listItems(roll.id)).single.files,
        containsAll(['R0000001.JPG', 'R0000001.DNG']));
    await repo.addConfirmedPhoto(
        rollId: roll.id,
        identity: identity(camera: 'camera-b'),
        recipe: catalog.recipe(75),
        files: ['R0000001.JPG'],
        confidence: RecipeConfidence.unverified);
    await repo.addConfirmedPhoto(
        rollId: roll.id,
        identity: identity(epoch: 'card-2'),
        recipe: catalog.recipe(67),
        files: ['R0000001.JPG'],
        confidence: RecipeConfidence.userAssigned);
    expect(await repo.listItems(roll.id), hasLength(3));
    expect((await repo.rolls()).single.confirmedCount, 3);
  });
  test('photo recipe is immutable after different recipe and roll closure',
      () async {
    final initial = catalog.recipe(33, parameters: {'grain': 1});
    final roll =
        await repo.createRoll(name: '一卷', targetCount: 1, recipe: initial);
    await repo.addConfirmedPhoto(
        rollId: roll.id,
        identity: identity(),
        recipe: initial,
        files: ['R0000001.JPG'],
        confidence: RecipeConfidence.unverified);
    await repo.closeRoll(roll.id);
    await repo.createRoll(
        name: '下一卷', targetCount: 36, recipe: catalog.recipe(75));
    expect((await repo.listItems(roll.id)).single.recipe.fingerprint,
        initial.fingerprint);
    expect((await repo.rolls()).where((r) => r.status == FilmRollStatus.open),
        hasLength(1));
  });
  test('unproven identity never silently becomes a confirmed photo', () async {
    final roll = await repo.createRoll(
        name: '一卷', targetCount: 36, recipe: catalog.recipe(33));
    const unknown = CameraPhotoIdentity(
        instanceId: 'a',
        storageId: 'sd',
        storageEpoch: '',
        dir: '100',
        baseName: 'R1');
    await expectLater(
        repo.addConfirmedPhoto(
            rollId: roll.id,
            identity: unknown,
            recipe: catalog.recipe(33),
            files: ['R1.JPG'],
            confidence: RecipeConfidence.unverified),
        throwsFormatException);
    expect(await repo.listItems(roll.id), isEmpty);
  });
  test('sync unknown outcome survives repository reload with full baseline',
      () async {
    final sync = SyncRepository(db);
    await sync.saveBaseline('camera-a', {
      'bootId': 'boot1',
      'revision': 'r1',
      'future': {'value': 3}
    });
    await sync.saveOperation(
        requestId: 'op-1',
        instanceId: 'camera-a',
        payload: {'baseRevision': 'r1', 'patch': []},
        status: 'unknown');
    final reloaded = SyncRepository(db);
    expect((await reloaded.baseline('camera-a'))!['future'], {'value': 3});
    expect((await reloaded.unresolved('camera-a')).single['status'], 'unknown');
  });
}
