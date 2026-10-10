import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/camera/recipe/combo_recipe.dart';
import 'package:gremote/camera/recipe/recipe_store.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _record = CaptureRecord(
  dir: '100RICOH',
  baseName: 'R0000001',
  files: ['R0000001.JPG'],
  wallSeconds: 1000,
  timeSource: TimeSource.camera,
  source: CaptureSource.app,
  effect: 'positiveFilm',
);

void main() {
  late Database db;
  late RecipeStore store;
  var now = DateTime.utc(2026, 10, 10);

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    now = DateTime.utc(2026, 10, 10);
    store =
        RecipeStore(db, clock: () => now = now.add(const Duration(seconds: 1)));
  });
  tearDown(() => db.close());

  test('the factory recipe is built in and never stored', () async {
    expect(ComboRecipe.factory.isFactory, isTrue);
    expect(await store.recipes(), isEmpty);
  });

  test('recipes are created in sort order and can be deleted', () async {
    final first = await store.create(name: '街头正片', effect: 'positiveFilm');
    final second = await store.create(name: '冷调', exportPresetId: 'preset-1');

    expect((await store.recipes()).map((r) => r.id), [first.id, second.id]);
    expect(second.sort, 1);
    expect(second.effect, isNull);

    await store.delete(first.id);
    expect((await store.recipes()).single.id, second.id);
  });

  test('names are required and limited to 24 characters', () async {
    expect(() => store.create(name: '  '), throwsArgumentError);
    expect(() => store.create(name: 'x' * 25), throwsArgumentError);
  });

  test('tags survive recipe deletion and can be confirmed', () async {
    final recipe = await store.create(name: '正片', effect: 'positiveFilm');
    await store.addTag(_record, recipe.id);
    await store.delete(recipe.id);

    final tag = (await store.tagsForBaseNames(['r0000001'])).single;
    expect(tag.recipeId, recipe.id);
    expect(tag.confirmed, isFalse);
    await store.confirmTag(tag.id);
    expect(
        (await store.tagsForBaseNames(['R0000001'])).single.confirmed, isTrue);
  });

  test('only the newest 50 program runs are kept', () async {
    for (var i = 0; i < 52; i++) {
      await store.saveRun({
        'id': 'run-$i',
        'kind': 'bracket',
        'config': {'i': i},
        'state': 'completed',
        'done': 1,
        'startedAt': i,
        'endedAt': i + 1,
        'log': const [],
      });
    }
    final ids = (await db.query('program_runs', orderBy: 'started_at'))
        .map((row) => row['id'])
        .toList();
    expect(ids, hasLength(50));
    expect(ids.first, 'run-2');
  });
}
