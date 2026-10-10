import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Set<String>> _tables(Database db) async => {
      for (final row in await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        row['name']! as String,
    };

void main() {
  setUpAll(sqfliteFfiInit);

  test('a new database is created at version 2 with every table', () async {
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    addTearDown(db.close);

    expect(await db.getVersion(), 2);
    expect(
      await _tables(db),
      containsAll([
        'local_media',
        'edit_documents',
        'export_presets',
        'luts',
        'app_kv',
        'combo_recipes',
        'capture_tags',
        'program_runs',
      ]),
    );
  });

  test('renames an existing legacy database without losing rows', () async {
    final dir = Directory.systemTemp.createTempSync('gremote-legacy-db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final legacyPath = '${dir.path}/m10v.db';
    final targetPath = '${dir.path}/gremote.db';
    final legacy = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: legacyPath);
    await legacy.insert('app_kv', {'key': 'saved', 'value': 'kept'});
    await legacy.close();

    final migrated = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: targetPath);
    addTearDown(migrated.close);
    expect(await File(targetPath).exists(), isTrue);
    expect(await File(legacyPath).exists(), isFalse);
    expect(await migrated.query('app_kv', where: 'key = ?', whereArgs: ['saved']),
        hasLength(1));
  });

  test('a version 1 database upgrades and keeps its rows', () async {
    final dir = Directory.systemTemp.createTempSync('gremote-db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/gremote.db';
    final v1 = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE local_media (
            media_id INTEGER PRIMARY KEY, uri TEXT NOT NULL,
            display_name TEXT NOT NULL, date_modified INTEGER NOT NULL,
            date_taken INTEGER, width INTEGER NOT NULL, height INTEGER NOT NULL,
            model TEXT, orientation INTEGER NOT NULL DEFAULT 1,
            exif_json TEXT, scanned INTEGER NOT NULL DEFAULT 0)'''),
      ),
    );
    await v1.insert('local_media', {
      'media_id': 7,
      'uri': 'content://7',
      'display_name': 'R0000007.JPG',
      'date_modified': 1,
      'width': 6000,
      'height': 4000,
    });
    await v1.close();

    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: path);
    addTearDown(db.close);

    expect(await db.getVersion(), 2);
    expect(
        await _tables(db),
        containsAll(
            ['app_kv', 'combo_recipes', 'capture_tags', 'program_runs']));
    expect(
        (await db.query('local_media')).single['display_name'], 'R0000007.JPG');
  });
}
