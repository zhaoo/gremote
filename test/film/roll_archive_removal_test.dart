import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/store/film_repository.dart';
import '../support/test_darkroom.dart';

void main() {
  test(
      'deleting a local archive removes its frame records and preserves photos and recipes',
      () async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final repo = FilmRepository(env.db);
    final catalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync())
            as Map<String, dynamic>);
    final roll = await repo.createRoll(
        name: '111', targetCount: 36, recipe: catalog.recipe(33));
    await env.db.insert('album_collection',
        {'media_id': 42, 'source': 'camera', 'added_at': 1});
    await env.db.insert('film_roll_items', {
      'id': 'frame',
      'roll_id': roll.id,
      'camera_key': 'camera/frame',
      'identity_json': '{}',
      'recipe_fingerprint': '',
      'recipe_json': '{}',
      'files_json': '["R0000001.JPG"]',
      'confidence': 'unverified',
      'media_id': 42,
      'created_at': 1,
      'selected': 0
    });
    await repo.deleteRollArchive(roll.id);
    expect(await repo.rolls(), isEmpty);
    expect(await env.db.query('film_roll_items'), isEmpty);
    expect(await env.db.query('album_collection'), hasLength(1));
    expect(await repo.recipe(roll.recipeFingerprint!), isNotNull);
    expect(env.gateway.shared, isEmpty);
  });
  test(
      'camera roll removal is scoped to persistent camera identity and roll ID',
      () async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final repo = FilmRepository(env.db);
    const id = '11111111111111111111111111111111';
    await repo.hideCameraRoll('camera-a', id);
    expect(await repo.hiddenCameraRolls('camera-a'), {id});
    expect(await repo.hiddenCameraRolls('camera-b'), isEmpty);
    expect(await FilmRepository(env.db).hiddenCameraRolls('camera-a'), {id});
    expect(await env.db.query('film_roll_items'), isEmpty);
  });
}
