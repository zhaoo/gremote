import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/capture/roll_capture_recorder.dart';
import 'package:gremote/film/capture/roll_reconciliation.dart';
import 'package:gremote/film/model/camera_photo_identity.dart';
import 'package:gremote/film/model/film_roll.dart';
import 'package:gremote/film/store/film_repository.dart';
import '../support/test_darkroom.dart';

void main() {
  test('disposed tracker cannot publish an in-flight camera response',
      () async {
    var calls = 0;
    final waiting = Completer<List<CameraFile>>();
    final tracker = CaptureTracker(
        listPhotos: () {
          calls++;
          return calls == 1 ? Future.value([]) : waiting.future;
        },
        captureWallSeconds: (_) async => 123);
    await tracker.prime();
    final detection = tracker.detect(
        const CaptureContext(source: CaptureSource.app),
        timeout: Duration.zero);
    tracker.dispose();
    waiting.complete([const CameraFile(dir: '100', file: 'R1.JPG')]);
    expect(await detection, isEmpty);
  });
  late TestDarkroom data;
  late FilmRepository repo;
  late FilmCatalog catalog;
  var generation = 1;
  setUp(() async {
    data = await TestDarkroom.create();
    repo = FilmRepository(data.db);
    catalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync())
            as Map<String, dynamic>);
    generation = 1;
  });
  tearDown(() async => data.close());
  CaptureRecord record(List<String> files) => CaptureRecord(
      dir: '100RICOH',
      baseName: 'R0000001',
      files: files,
      wallSeconds: 123,
      timeSource: TimeSource.camera,
      source: CaptureSource.body);
  test('missing file confirmation and stale session never create a roll item',
      () async {
    final roll = await repo.createRoll(
        name: '散步', targetCount: 36, recipe: catalog.recipe(33));
    final recorder = RollCaptureRecorder(repo, generation: () => generation);
    final evidence = RecipeEvidence(
        rollId: roll.id,
        recipe: catalog.recipe(33),
        identity: const CameraPhotoIdentity(
            instanceId: 'camera',
            storageId: 'sd',
            storageEpoch: 'card1',
            dir: '100RICOH',
            baseName: 'R0000001',
            captureId: 'shot1'),
        sessionGeneration: 1,
        confidence: RecipeConfidence.unverified);
    await recorder.record(record([]), evidence);
    expect(await repo.listItems(roll.id), isEmpty);
    generation = 2;
    await recorder.record(record(['R0000001.JPG']), evidence);
    expect(await repo.listItems(roll.id), isEmpty);
  });
  test('late RAW enriches the frozen photo even after closing its roll',
      () async {
    final recipe = catalog.recipe(33, parameters: {'grain': 2});
    final roll =
        await repo.createRoll(name: '散步', targetCount: 36, recipe: recipe);
    final recorder = RollCaptureRecorder(repo, generation: () => generation);
    await recorder.record(
        record(['R0000001.JPG']),
        RecipeEvidence(
            rollId: roll.id,
            recipe: recipe,
            identity: const CameraPhotoIdentity(
                instanceId: 'camera',
                storageId: 'sd',
                storageEpoch: 'card1',
                dir: '100RICOH',
                baseName: 'R0000001',
                captureId: 'shot1'),
            sessionGeneration: 1,
            confidence: RecipeConfidence.unverified));
    await repo.closeRoll(roll.id);
    await repo.createRoll(
        name: '下一卷', targetCount: 36, recipe: catalog.recipe(75));
    await recorder.appendFiles(const CaptureFileUpdate(
        dir: '100RICOH', baseName: 'R0000001', files: ['R0000001.DNG']));
    final item = (await repo.listItems(roll.id)).single;
    expect(item.files, hasLength(2));
    expect(item.recipe.fingerprint, recipe.fingerprint);
    expect(item.confidence, RecipeConfidence.unverified);
  });
  test('reconnection only proposes new groups without assigning them',
      () async {
    final before = CameraPhotoBaseline(
        instanceId: 'camera',
        storageId: 'sd',
        storageEpoch: 'card1',
        files: [const CameraFile(dir: '100', file: 'R1.JPG')]);
    final candidates = RollReconciliation.candidates(before: before, after: [
      const CameraFile(dir: '100', file: 'R1.JPG'),
      const CameraFile(dir: '100', file: 'R1.DNG'),
      const CameraFile(dir: '100', file: 'R2.JPG'),
      const CameraFile(dir: '100', file: 'R2.DNG')
    ]);
    expect(candidates, hasLength(1));
    expect(candidates.single.files, hasLength(2));
    expect(candidates.single.identity.isStable, isFalse);
    expect(await repo.rolls(), isEmpty);
  });
  test(
      'capture tracker freezes roll context and reports late file updates separately',
      () async {
    final files = <CameraFile>[];
    final tracker = CaptureTracker(
        listPhotos: () async => List.of(files),
        captureWallSeconds: (_) async => 123);
    addTearDown(tracker.dispose);
    final updates = <CaptureFileUpdate>[];
    tracker.fileUpdates.listen(updates.add);
    await tracker.prime();
    files.add(const CameraFile(dir: '100', file: 'R1.JPG'));
    final rec = (await tracker.detect(
            const CaptureContext(
                source: CaptureSource.app,
                filmRollId: 'roll1',
                filmRecipeJson: 'frozen'),
            timeout: Duration.zero))
        .single;
    files.add(const CameraFile(dir: '100', file: 'R1.DNG'));
    expect(
        await tracker.detect(const CaptureContext(source: CaptureSource.body),
            timeout: Duration.zero),
        isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(updates.single.files, contains('R1.DNG'));
    expect(rec.filmRecipeJson, 'frozen');
    expect(rec.filmRollId, 'roll1');
  });
}
