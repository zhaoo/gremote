import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens the single app database and owns its schema.
abstract final class GRemoteDatabase {
  static const version = 2;

  static Future<Database> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await dbFactory.getDatabasesPath(), 'gremote.db');
    if (dbPath != inMemoryDatabasePath &&
        !await dbFactory.databaseExists(dbPath)) {
      final legacyPath = p.join(p.dirname(dbPath), 'm10v.db');
      if (await dbFactory.databaseExists(legacyPath)) {
        for (final suffix in ['', '-wal', '-shm', '-journal']) {
          final legacyFile = File('$legacyPath$suffix');
          if (await legacyFile.exists()) {
            await legacyFile.rename('$dbPath$suffix');
          }
        }
      }
    }
    return dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
  }

  static Future<void> _create(Database db, int version) async {
    await _createV1(db);
    await _createV2(db);
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _createV2(db);
  }

  static Future<void> _createV1(Database db) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE local_media (
          media_id INTEGER PRIMARY KEY,
          uri TEXT NOT NULL,
          display_name TEXT NOT NULL,
          date_modified INTEGER NOT NULL,
          date_taken INTEGER,
          width INTEGER NOT NULL,
          height INTEGER NOT NULL,
          model TEXT,
          orientation INTEGER NOT NULL DEFAULT 1,
          exif_json TEXT,
          scanned INTEGER NOT NULL DEFAULT 0
        )''')
      ..execute('CREATE INDEX local_media_taken ON local_media(date_taken)')
      ..execute('''
        CREATE TABLE edit_documents (
          media_id INTEGER PRIMARY KEY,
          recipe_json TEXT NOT NULL,
          title TEXT NOT NULL,
          location TEXT NOT NULL,
          hidden_fields_json TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE TABLE export_presets (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          recipe_json TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE TABLE luts (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          source TEXT NOT NULL,
          size INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          sha256 TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL
        )''');
    await batch.commit(noResult: true);
  }

  /// Remote control: protocol profile, combo recipes, capture tags and
  /// program logs.
  static Future<void> _createV2(Database db) async {
    final batch = db.batch()
      ..execute(
          'CREATE TABLE app_kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
      ..execute('''
        CREATE TABLE combo_recipes (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          effect TEXT,
          export_preset_id TEXT,
          sort INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE TABLE capture_tags (
          id INTEGER PRIMARY KEY,
          base_name TEXT NOT NULL,
          dir TEXT NOT NULL,
          captured_at INTEGER NOT NULL,
          time_source TEXT NOT NULL,
          combo_recipe_id TEXT NOT NULL,
          effect TEXT,
          program_run_id TEXT,
          confirmed INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )''')
      ..execute('CREATE INDEX capture_tags_name ON capture_tags(base_name)')
      ..execute('''
        CREATE TABLE program_runs (
          id TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          config_json TEXT NOT NULL,
          state TEXT NOT NULL,
          frames_done INTEGER NOT NULL,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          log_json TEXT NOT NULL
        )''');
    await batch.commit(noResult: true);
  }
}
