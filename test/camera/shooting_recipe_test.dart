import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/camera/params/camera_param.dart';
import 'package:gremote/camera/params/param_writer.dart';
import 'package:gremote/camera/recipe/shooting_recipe.dart';
import 'package:gremote/camera/sync/camera_state.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('embedded body recipe requires the exact custom content hash', () {
    final payload = Uint8List(176);
    payload.setAll(0, 'MCR2'.codeUnits);
    final words = ByteData.sublistView(payload);
    words.setUint32(12, 25, Endian.little);
    words.setUint16(16, 79, Endian.little);
    payload[30] = 21;
    words.setUint16(68, 5600, Endian.little);
    payload[72] = 0;
    payload[73] = 0;
    payload[74] = 12;
    payload[75] = 15;
    payload.fillRange(76, 108, 0xcc);
    payload.fillRange(108, 140, 0xaa);
    payload.fillRange(140, 172, 0xbb);
    words.setUint32(172, exposureRecipeCrc(payload, 172), Endian.little);
    final hex = payload.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    final recipe = RecordedExposure.parse(hex, 0x2000)!;
    expect(recipe.filmId, 79);
    expect(recipe.kelvin, 5600);
    expect(recipe.whiteBalanceShift, (2, -1));
    expect(recipe.matchesFilm({'filmId': 79, 'customHash': 'cc' * 32}), isTrue);
    expect(
        recipe.matchesFilm({'filmId': 79, 'customHash': 'cd' * 32}), isFalse);
    expect(RecordedExposure.parse(hex, 0x2001), isNull);
    expect(RecordedExposure.parse('${hex.substring(0, 344)}00000000', 0x2000),
        isNull);
  });
  test('one capture resolves the same snapshot for its JPG and late DNG',
      () async {
    sqfliteFfiInit();
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final store = ShootingRecipeStore(db);
    final recipe = ShootingRecipe(
        name: '街拍',
        catalog: 'a' * 64,
        renderer: 'b' * 64,
        film: {
          'filmId': 331,
          'parameters': {'grain': 2}
        },
        settings: {
          'WBMode': 'daylight'
        },
        effects: {
          'hdf': 1
        });
    const shot = CaptureRecord(
        dir: '100RICOH',
        baseName: 'R001',
        files: ['R001.JPG'],
        wallSeconds: 1234,
        timeSource: TimeSource.camera,
        source: CaptureSource.app);
    await store.rememberCapture('cameraA', shot, recipe);
    const dng = CameraFile(dir: '100RICOH', file: 'R001.DNG');
    final original =
        await store.captureRecipe('cameraA', shot.primaryFile, 1234, 0x114b);
    final raw = await store.captureRecipe('cameraA', dng, 1234, 0x114b);
    expect(original?.toJson(), recipe.toJson());
    expect(raw?.toJson(), recipe.toJson());
    expect(await store.captureRecipe('cameraB', dng, 1234, 0x114b), isNull);
    expect(await store.captureRecipe('cameraA', dng, 1235, 0x114b), isNull);
    expect(await store.captureRecipe('cameraA', dng, 1234, 0x114c), isNull);
    await store.rememberPhotoFilm('content://photo', 0x114b, 'a' * 64,
        recipe: raw);
    expect((await store.photoFilm('content://photo'))?.recipe?.toJson(),
        recipe.toJson());

    final reused = ShootingRecipe.fromJson({
      ...recipe.toJson(),
      'settings': {'WBMode': 'auto'},
    });
    await store.rememberCapture('cameraA', shot, reused);
    expect(await store.captureRecipe('cameraA', dng, 1234, 0x114b), isNull);
  });
  test('matching a photo uses the recorded identity, not legacy slot tones',
      () {
    expect(recordedBuiltinFilmId(0x114b), 331);
    expect(recordedBuiltinFilmId(0x10c), isNull);
    expect(recordedBuiltinFilmId(0x2010), isNull);
  });
  test('body snapshots remain attached to each original without app capture',
      () async {
    sqfliteFfiInit();
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final store = ShootingRecipeStore(db);
    final first = '4d435231${'01' * 76}';
    final second = '4d435231${'02' * 76}';
    await store.rememberPhotoFilm('content://R001.JPG', 0x114b, 'a' * 64,
        exposureRecipe: first);
    await store.rememberPhotoFilm('content://R001.DNG', 0x114b, 'b' * 64,
        exposureRecipe: first);
    await store.rememberPhotoFilm('content://R002.DNG', 0x114b, 'c' * 64,
        exposureRecipe: second);
    expect(
        (await store.photoFilm('content://R001.JPG'))?.exposureRecipe, first);
    expect(
        (await store.photoFilm('content://R001.DNG'))?.exposureRecipe, first);
    expect(
        (await store.photoFilm('content://R002.DNG'))?.exposureRecipe, second);
    expect((await store.photoFilm('content://R002.DNG'))?.recipe, isNull);
  });

  test('recipe preflight refuses settings it cannot restore', () {
    final state = CameraState(params: {
      'WBMode': CameraParam.forWire('WBMode',
          current: 'auto', options: const ['auto', 'daylight']),
      'tv':
          CameraParam.forWire('tv', current: '1/250', options: const ['1/250']),
    });
    expect(recipeChanges(state, {'WBMode': 'daylight'}), {
      'WBMode': 'daylight',
    });
    expect(() => recipeChanges(state, {'WBMode': 'daylight', 'tv': '1/125'}),
        throwsFormatException);
  });

  test('a mismatched readback stops subsequent writes', () async {
    final writes = <String>[];
    await expectLater(
      writeRecipeSettings({'WBMode': 'daylight', 'sv': '400'},
          (key, value) async {
        writes.add(key);
        return const WriteCorrected('auto');
      }, () => true),
      throwsStateError,
    );
    expect(writes, ['WBMode']);
  });
}
