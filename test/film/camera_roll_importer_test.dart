import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/film/capture/camera_roll_importer.dart';
import 'package:gremote/film/export/contact_sheet_layout.dart';
import 'package:gremote/film/model/film_roll.dart';
import 'package:gremote/film/store/film_repository.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const first =
      '4d3130520102030405060708090a0b0c0d0e0f10010000000c000000babacab3';
  const seventh =
      '4d3130520102030405060708090a0b0c0d0e0f10070000000c0000003db3a575';
  const oneRaw = CameraFile(dir: '100RICOH', file: 'R0000100.DNG');
  const oneJpeg = CameraFile(dir: '100RICOH', file: 'R0000100.JPG');
  const sevenJpeg = CameraFile(dir: '101RICOH', file: 'R0000002.JPG');

  test('the frame envelope validates CRC, order and target', () {
    final frame = CameraRollFrame.parse(first);
    expect(frame?.rollId, '0102030405060708090a0b0c0d0e0f10');
    expect(frame?.number, 1);
    expect(frame?.targetCount, 12);
    expect(CameraRollFrame.parse('${first.substring(0, 62)}00'), isNull);
  });

  test('out-of-order downloads merge a pair and preserve frame order',
      () async {
    sqfliteFfiInit();
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final repository = FilmRepository(db);
    final importer = CameraRollImporter(repository);

    await importer.import(sevenJpeg, CameraRollFrame.parse(seventh)!,
        hash: 'a' * 64, mediaId: 7);
    await importer.import(oneRaw, CameraRollFrame.parse(first)!,
        hash: 'b' * 64);
    await importer.import(oneJpeg, CameraRollFrame.parse(first)!,
        hash: 'c' * 64, mediaId: 1);
    await importer.import(oneJpeg, CameraRollFrame.parse(first)!,
        hash: 'c' * 64, mediaId: 10);

    final roll = (await repository.rolls()).single;
    final frames = await FilmRepository(db).listItems(roll.id);
    expect(roll.targetCount, 12);
    expect(roll.status, FilmRollStatus.archived);
    expect(roll.recipeFingerprint, isNull);
    expect(roll.confirmedCount, 2);
    expect(frames.map((item) => item.frameNumber), [1, 7]);
    expect(frames.first.files, [oneRaw.file, oneJpeg.file]);
    expect(frames.first.mediaId, 10);
    expect(frames.first.previewHash, 'c' * 64);
    expect(frames.first.recipe, isNull);
    expect(frames.first.confidence, RecipeConfidence.unverified);
    expect(ContactSheetLayout.pages(frames).single.items, frames);

    await expectLater(
        importer.import(oneJpeg, CameraRollFrame.parse(first)!,
            hash: 'd' * 64, mediaId: 11),
        throwsStateError);
    await expectLater(
        importer.import(sevenJpeg, CameraRollFrame.parse(first)!,
            hash: 'a' * 64, mediaId: 7),
        throwsStateError);
    expect((await repository.listItems(roll.id)).first.mediaId, 10);
  });
}
