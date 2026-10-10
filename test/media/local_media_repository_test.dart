import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/model/edit_document.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/darkroom/model/photo_meta.dart';
import 'package:gremote/darkroom/store/darkroom_store.dart';
import 'package:gremote/media/local/local_media_repository.dart';
import 'package:gremote/media/local/media_gateway.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_media_gateway.dart';

LocalMediaEntry entry(int id, {int modified = 100, int? taken}) =>
    LocalMediaEntry(
      id: id,
      uri: 'content://media/external/images/media/$id',
      displayName: 'R00$id.JPG',
      dateModified: modified,
      dateTaken: taken ?? id * 1000,
      width: 6000,
      height: 4000,
    );

PhotoMeta meta(String model) =>
    PhotoMeta(width: 6000, height: 4000, model: model);

void main() {
  sqfliteFfiInit();
  late Database db;
  late FakeMediaGateway gateway;
  late LocalMediaRepository repository;

  setUp(() async {
    db = await GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    gateway = FakeMediaGateway(
      entries: [entry(1), entry(2), entry(3)],
      exif: {
        1: meta('RICOH GR III'),
        2: meta('Xiaomi 14'),
        3: meta(' ricoh gr iii '),
      },
    );
    repository = LocalMediaRepository(db, gateway, batchSize: 2);
  });

  tearDown(() => db.close());

  group('LocalMediaRepository', () {
    test('first scan reads EXIF in batches and reports progress', () async {
      final progress = await repository.scan().toList();
      expect(progress.map((p) => p.done), [0, 2, 3]);
      expect(progress.last.total, 3);
      expect(gateway.exifRequests, [
        [1, 2],
        [3],
      ]);
      final all = await repository.list(grOnly: false);
      expect(all.map((i) => i.id), [3, 2, 1]);
      expect(all.first.meta?.model, ' ricoh gr iii ');
    });

    test('GR filter matches the GR III model only', () async {
      await repository.scan().drain<void>();
      final gr = await repository.list(grOnly: true);
      expect(gr.map((i) => i.id), [3, 1]);
      expect(gr.every((i) => i.isGrIII), isTrue);
    });

    test('rescans only changed rows and drops vanished ones', () async {
      await repository.scan().drain<void>();
      gateway.exifRequests.clear();
      gateway.entries = [entry(1), entry(3, modified: 200)];
      await repository.scan().drain<void>();
      expect(gateway.exifRequests, [
        [3],
      ]);
      final all = await repository.list(grOnly: false);
      expect(all.map((i) => i.id), [3, 1]);
      expect(await repository.find(2), isNull);
      expect((await repository.find(1))?.meta?.model, 'RICOH GR III');
    });
  });

  group('DarkroomStore', () {
    late DarkroomStore store;
    setUp(() => store = DarkroomStore(db));

    test('saves edits and lists the most recent first', () async {
      await store.saveEdit(EditDocument(
          mediaId: 1,
          title: 'a',
          hidden: const {FrameField.iso},
          updatedAt: DateTime.utc(2026, 1, 1)));
      await store.saveEdit(EditDocument(
          mediaId: 2,
          recipe: const ExportRecipe(frame: FrameStyle.contact),
          updatedAt: DateTime.utc(2026, 2, 1)));
      await store.saveEdit(EditDocument(
          mediaId: 1, title: 'b', updatedAt: DateTime.utc(2026, 3, 1)));
      final recent = await store.recentEdits();
      expect(recent.map((d) => d.mediaId), [1, 2]);
      expect(recent.first.title, 'b');
      expect((await store.loadEdit(2))?.recipe.frame, FrameStyle.contact);
      expect(await store.loadEdit(9), isNull);
    });

    test('manages presets', () async {
      final preset = await store.savePreset(
          '街拍', const ExportRecipe(lutId: 'builtin:pale'));
      await store.renamePreset(preset.id, '夜街');
      final presets = await store.presets();
      expect(presets.single.name, '夜街');
      expect(presets.single.recipe.lutId, 'builtin:pale');
      await store.deletePreset(preset.id);
      expect(await store.presets(), isEmpty);
    });

    test('deduplicates imported LUTs by hash', () async {
      final first = await store.addImportedLut(
          name: 'A', size: 33, sha256: 'abc', filePath: '/x/abc.cube');
      final again = await store.addImportedLut(
          name: 'B', size: 33, sha256: 'abc', filePath: '/x/abc.cube');
      expect(again.id, first.id);
      expect(again.name, 'A');
      expect(await store.importedLuts(), hasLength(1));
      await store.deleteLut(first.id);
      expect(await store.importedLuts(), isEmpty);
    });
  });
}
