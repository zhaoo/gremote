import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/features/film_workbench/workbench_providers.dart';
import 'package:gremote/film/capture/active_roll_context.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/store/film_repository.dart';

void main() {
  test('restart hydrates frozen active recipe before workbench is opened',
      () async {
    sqfliteFfiInit();
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final repo = FilmRepository(db),
        catalog = FilmCatalog.fromJson(
            jsonDecode(File('assets/films/catalog.json').readAsStringSync())
                as Map<String, dynamic>);
    final recipe = catalog.recipe(33),
        roll = await repo.createRoll(
            name: '日常', targetCount: 36, recipe: catalog.recipe(33));
    final container =
        ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    await container.read(activeRollHydrationProvider.future);
    expect(container.read(activeRollCaptureContextProvider)!.rollId, roll.id);
    expect(
        jsonDecode(
            container.read(activeRollCaptureContextProvider)!.recipeJson),
        recipe.toJson());
    await repo.closeRoll(roll.id);
    container.read(filmRollRevisionProvider.notifier).state++;
    await container.read(activeRollHydrationProvider.future);
    expect(container.read(activeRollCaptureContextProvider), isNull);
  });
}
