import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'package:gremote/camera/companion/generated_camera_contract.dart';
import 'package:gremote/camera/companion/three_way_merge.dart';

Map<String, dynamic> cameraStateFixture() => {
      'protocol': 1,
      'schemaVersion': 2,
      'bootId': '02' * 16,
      'instanceId': '01' * 16,
      'catalogHash': cameraCatalogHash,
      'rendererHash': cameraRendererHash,
      'revision': '03' * 32,
      'configHash': '04' * 32,
      'journalSequence': 1,
      'activeSlot': 9,
      'busy': false,
      'fresh': true,
      'config': {
        'slots': List.generate(
            10,
            (i) => {
                  'filmId': i == 9 ? 321 : 34 + i,
                  'customHash': null,
                  'parameters': {
                    'grain': 0,
                    'grainSize': 1,
                    'haloGain': 0,
                    'haloSpread': 3,
                    'haloThreshold': 5,
                    'haloProfile': 6,
                    'leakGain': 0,
                    'leakPosition': 0,
                    'leakSpread': 4,
                    'leakVariation': 0
                  }
                }),
        'globals': {
          'stamp': 0,
          'format': 0,
          'corner': 0,
          'color': 0,
          'filmNameStamp': 0
        }
      }
    };
Map<String, dynamic> cameraCapabilitiesFixture() => {
      'protocol': 1,
      'model': 'GR III',
      'recipeSchema': 1,
      'stateSchema': 2,
      'slotCount': 10,
      'firmwareIdentity': cameraContract['officialFirmwareSha256'],
      'bootId': '02' * 16,
      'sessionId': '05' * 16,
      'instanceId': '01' * 16,
      'buildId': '06' * 32,
      'catalogHash': cameraCatalogHash,
      'rendererHash': cameraRendererHash,
      'capabilities': {
        'readState': true,
        'writeState': true,
        'uploadFilm': false,
        'captureEvidence': false
      },
      'parameters': cameraContract['parameters'],
      'limits': cameraContract['limits'],
      'readOnlyParameters': cameraContract['readOnlyParameters']
    };
void main() {
  test('latest C41 camera recipes use the camera contract bound', () {
    expect(cameraContract['maximumFilmId'], 326);
    for (var id = 322; id <= 326; id++) {
      final recipe = CameraFilmRecipe.fromJson({
        'schemaVersion': 1,
        'filmId': id,
        'catalogHash': cameraCatalogHash,
        'rendererHash': cameraRendererHash,
        'parameters': {'grain': 1},
        'name': 'C41'
      });
      expect(recipe.filmId, id);
    }
    expect(
        () => CameraFilmRecipe.fromJson({
              'schemaVersion': 1,
              'filmId': 327,
              'catalogHash': cameraCatalogHash,
              'rendererHash': cameraRendererHash,
              'parameters': <String, int>{}
            }),
        throwsFormatException);
  });
  late CameraFilmCatalog camera;
  late FilmCatalog legacy;
  setUp(() {
    camera = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-catalog.json').readAsStringSync()));
    legacy = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync()));
  });
  test(
      'ten-slot state retains empty slots and newest film and rejects old layout',
      () {
    final state = CompanionSnapshot.fromJson(cameraStateFixture(),
        contract: cameraContract);
    expect(state.activeSlot, 9);
    expect(state.slots.length, 10);
    expect(state.slots.first['filmId'], 34);
    final empty = cameraStateFixture();
    empty['config']['slots'][9] = {
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
    empty['activeSlot'] = 8;
    expect(
        CompanionSnapshot.fromJson(empty, contract: cameraContract)
            .slots
            .last['filmId'],
        0);
    expect(state.recipeAt(9).filmId, 321);
    expect(state.hasUnknownFields, false);
    final wrong = cameraStateFixture()..['schemaVersion'] = 1;
    expect(() => CompanionSnapshot.fromJson(wrong, contract: cameraContract),
        throwsFormatException);
  });
  test(
      'camera recipe exact hashes and parameters cannot enter old local parser',
      () {
    final r = camera.recipe(321);
    expect(r.parameters['haloProfile'], 6);
    expect(
        () => CameraFilmRecipe.fromJson(
            {...r.toJson(), 'rendererHash': legacy.rendererHash}),
        throwsFormatException);
    expect(() => legacy.recipe(321), throwsFormatException);
  });
  test('legacy migration is explicit and preserves target retired parameters',
      () {
    final old = legacy.recipe(33, parameters: {'haloGain': 2});
    final original = old.fingerprint;
    final target = camera
        .recipe(321, parameters: {'grainSize': 2, 'leakPosition': 5}).toJson();
    final migrated = camera.forTarget(old, target);
    expect(migrated.filmId, 33);
    expect(migrated.parameters['haloProfile'], 4);
    expect(migrated.parameters['grainSize'], 2);
    expect(migrated.parameters['leakPosition'], 5);
    expect(migrated.rendererHash, cameraRendererHash);
    expect(old.fingerprint, original);
    expect(
        () => camera.forTarget(
            legacy.recipe(33, parameters: {'leakGain': 1}), target),
        throwsFormatException);
    expect(
        () => camera.forTarget(
            legacy.recipe(33, parameters: {'grainSize': 2}), target),
        throwsFormatException);
    expect(() => camera.forTarget(legacy.recipe(38), target),
        throwsFormatException);
  });
  test(
      'Charmera exposes preserved bytes and native load canonicalizes retired leak gain',
      () {
    final target = camera.recipe(321, parameters: {
      'grainSize': 2,
      'leakGain': 3,
      'leakPosition': 5
    }).toJson();
    final migrated = camera.forTarget(camera.recipe(289), target);
    expect(migrated.parameters['grainSize'], 2);
    expect(migrated.parameters['leakGain'], 0);
    expect(migrated.parameters['leakPosition'], 5);
    final replacement = camera.forTarget(camera.recipe(33), migrated.toJson());
    expect(replacement.parameters['grainSize'], 2);
    expect(replacement.parameters['leakPosition'], 5);
  });
  test(
      'schema2 compatibility and merge refuse duplicate ids and unknown parameters',
      () {
    final caps = CompanionCapabilities.fromJson(cameraCapabilitiesFixture(),
        contract: cameraContract);
    expect(caps.compatibleWith(cameraCatalogHash, cameraRendererHash), true);
    final old = cameraCapabilitiesFixture()..['stateSchema'] = 1;
    expect(
        CompanionCapabilities.fromJson(old, contract: cameraContract)
            .compatibleWith(cameraCatalogHash, cameraRendererHash),
        false);
    final state = CompanionSnapshot.fromJson(cameraStateFixture(),
        contract: cameraContract);
    expect(knownCompanionConfig(state.config, contract: cameraContract), true);
    final duplicate =
        jsonDecode(jsonEncode(state.config)) as Map<String, dynamic>;
    (duplicate['slots'] as List)[0] = (duplicate['slots'] as List)[9];
    expect(knownCompanionConfig(duplicate, contract: cameraContract), false);
    final gap = jsonDecode(jsonEncode(state.config)) as Map<String, dynamic>;
    gap['slots'][0] = {'filmId': 0, 'parameters': {}, 'customHash': null};
    expect(knownCompanionConfig(gap, contract: cameraContract), false);
    final unknown = cameraStateFixture();
    ((unknown['config']['slots'] as List)[9]['parameters'] as Map)['future'] =
        1;
    expect(
        CompanionSnapshot.fromJson(unknown, contract: cameraContract)
            .hasUnknownFields,
        true);
  });
}
