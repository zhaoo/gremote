import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/capture/local_roll_importer.dart';
import 'package:gremote/film/model/film_roll.dart';
import 'package:gremote/film/store/film_repository.dart';
import '../support/fake_media_gateway.dart';

void main() {
  test(
      'import uses original content identity and immutable user-assigned recipe',
      () async {
    sqfliteFfiInit();
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final repo = FilmRepository(db), gateway = FakeMediaGateway();
    final catalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync())
            as Map<String, dynamic>);
    final recipe = catalog.recipe(33),
        roll = await repo.createRoll(
            name: '散步', targetCount: 36, recipe: catalog.recipe(33));
    final importer = LocalRollImporter(repository: repo, gateway: gateway);
    gateway.contentHashes.addAll({1: 'a' * 64, 2: 'a' * 64, 3: 'b' * 64});
    await importer.import(rollId: roll.id, mediaId: 1, recipe: recipe);
    await importer.import(
        rollId: roll.id, mediaId: 2, recipe: catalog.recipe(34));
    final first = (await repo.listItems(roll.id)).single;
    expect(first.recipe.fingerprint, recipe.fingerprint);
    expect(first.confidence, RecipeConfidence.userAssigned);
    await importer.import(rollId: roll.id, mediaId: 3, recipe: recipe);
    expect(await repo.listItems(roll.id), hasLength(2));
    await expectLater(
        importer.import(rollId: roll.id, mediaId: 4, recipe: recipe),
        throwsStateError);
    expect(await repo.listItems(roll.id), hasLength(2));
  });
}
