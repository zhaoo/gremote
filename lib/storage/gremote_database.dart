import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens the single app database and owns its schema.
abstract final class GRemoteDatabase {
  static const version = 6;

  static Future<Database> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), 'gremote.db');
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
    await _createV3(db);
    await _createV4(db);
    await _createV5(db);
    await _createV6(db);
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _createV2(db);
    if (from < 3) await _createV3(db);
    if (from < 4) await _createV4(db);
    if (from < 5) await _createV5(db);
    if (from < 6) await _createV6(db);
  }

  static Future<void> _createV6(Database db) => db.execute(
      "CREATE TABLE album_collection (media_id INTEGER PRIMARY KEY, source TEXT NOT NULL, added_at INTEGER NOT NULL, source_hash TEXT UNIQUE)");

  static Future<void> _createV5(Database db) => db.execute(
      'CREATE TABLE camera_film_recipes (fingerprint TEXT PRIMARY KEY, recipe_json TEXT NOT NULL, created_at INTEGER NOT NULL)');

  static Future<void> _createV4(Database db) async {
    final batch = db.batch()
      ..execute(
          'CREATE TABLE film_recipes (fingerprint TEXT PRIMARY KEY, recipe_json TEXT NOT NULL, created_at INTEGER NOT NULL)')
      ..execute(
          '''CREATE TABLE film_rolls (id TEXT PRIMARY KEY, name TEXT NOT NULL,
        target_count INTEGER NOT NULL CHECK(target_count BETWEEN 1 AND 999),
        recipe_fingerprint TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('open','closed','archived')),
        created_at INTEGER NOT NULL, closed_at INTEGER)''')
      ..execute(
          "CREATE UNIQUE INDEX film_rolls_one_open ON film_rolls(status) WHERE status='open'")
      ..execute(
          '''CREATE TABLE film_roll_items (id TEXT PRIMARY KEY, roll_id TEXT NOT NULL,
        camera_key TEXT NOT NULL UNIQUE, identity_json TEXT NOT NULL,
        recipe_fingerprint TEXT NOT NULL, recipe_json TEXT NOT NULL, files_json TEXT NOT NULL,
        confidence TEXT NOT NULL, media_id INTEGER, created_at INTEGER NOT NULL,
        selected INTEGER NOT NULL DEFAULT 0)''')
      ..execute(
          'CREATE INDEX film_roll_items_roll ON film_roll_items(roll_id,created_at)')
      ..execute(
          'CREATE TABLE camera_sync_baselines (instance_id TEXT PRIMARY KEY,snapshot_json TEXT NOT NULL,updated_at INTEGER NOT NULL)')
      ..execute(
          'CREATE TABLE camera_sync_operations (request_id TEXT PRIMARY KEY,instance_id TEXT NOT NULL,payload_json TEXT NOT NULL,status TEXT NOT NULL,updated_at INTEGER NOT NULL)');
    await batch.commit(noResult: true);
  }

  static Future<void> _createV3(Database db) async {
    await db.execute('''
      CREATE TABLE shot_locations (
        dir TEXT NOT NULL, base_name TEXT NOT NULL,
        capture_wall_seconds INTEGER NOT NULL, recorded_at INTEGER NOT NULL,
        latitude REAL NOT NULL, longitude REAL NOT NULL, accuracy REAL NOT NULL,
        altitude REAL, measured_at INTEGER NOT NULL,
        PRIMARY KEY (dir, base_name, capture_wall_seconds)
      )''');
    await db.execute(
        'CREATE INDEX shot_locations_recorded ON shot_locations(recorded_at)');
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
