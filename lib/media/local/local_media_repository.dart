import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:sqflite/sqflite.dart';

import '../../darkroom/model/photo_meta.dart';
import 'media_gateway.dart';

const grIIIModel = 'RICOH GR III';

bool isGrIIIModel(String? model) =>
    model != null && model.trim().toUpperCase() == grIIIModel;

@immutable
class LocalMediaItem {
  const LocalMediaItem({
    required this.id,
    required this.uri,
    required this.displayName,
    required this.dateModified,
    this.dateTaken,
    this.meta,
  });

  final int id;
  final String uri;
  final String displayName;
  final int dateModified;
  final int? dateTaken;

  /// Null until the EXIF scan has reached this row.
  final PhotoMeta? meta;

  bool get isGrIII => isGrIIIModel(meta?.model);
}

@immutable
class ScanProgress {
  const ScanProgress(this.done, this.total);

  final int done;
  final int total;
}

/// Mirrors MediaStore JPEGs into SQLite and reads EXIF incrementally.
class LocalMediaRepository {
  LocalMediaRepository(this._db, this._gateway, {this.batchSize = 50});

  final Database _db;
  final MediaGateway _gateway;
  final int batchSize;

  Stream<ScanProgress> scan() async* {
    final entries = await _gateway.queryImages();
    final known = {
      for (final row in await _db.query('local_media',
          columns: ['media_id', 'date_modified', 'scanned']))
        row['media_id']! as int: row,
    };
    final current = {for (final e in entries) e.id};
    final vanished = known.keys.where((id) => !current.contains(id)).toList();
    final stale = entries.where((e) {
      final row = known[e.id];
      return row == null ||
          row['date_modified'] != e.dateModified ||
          row['scanned'] != 1;
    }).toList();

    final cleanup = _db.batch();
    for (final id in vanished) {
      cleanup.delete('local_media', where: 'media_id = ?', whereArgs: [id]);
    }
    for (final e in stale) {
      cleanup.insert('local_media', _entryRow(e),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await cleanup.commit(noResult: true);

    yield ScanProgress(0, stale.length);
    for (var start = 0; start < stale.length; start += batchSize) {
      final chunk = stale.skip(start).take(batchSize).toList();
      final metas = await _gateway.readExif([for (final e in chunk) e.id]);
      final batch = _db.batch();
      for (final e in chunk) {
        final meta = metas[e.id];
        batch.update(
          'local_media',
          {
            'model': meta?.model,
            'orientation': meta?.orientation ?? 1,
            'exif_json': meta == null ? null : jsonEncode(meta.toJson()),
            'scanned': 1,
          },
          where: 'media_id = ?',
          whereArgs: [e.id],
        );
      }
      await batch.commit(noResult: true);
      yield ScanProgress(start + chunk.length, stale.length);
    }
  }

  Future<List<LocalMediaItem>> list({required bool grOnly}) async {
    final rows = await _db.query(
      'local_media',
      where: grOnly ? 'upper(trim(model)) = ?' : null,
      whereArgs: grOnly ? [grIIIModel] : null,
      orderBy: 'coalesce(date_taken, date_modified * 1000) DESC, media_id DESC',
    );
    return rows.map(_item).toList();
  }

  Future<LocalMediaItem?> find(int id) async {
    final rows = await _db.query('local_media',
        where: 'media_id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _item(rows.single);
  }

  Map<String, Object?> _entryRow(LocalMediaEntry e) => {
        'media_id': e.id,
        'uri': e.uri,
        'display_name': e.displayName,
        'date_modified': e.dateModified,
        'date_taken': e.dateTaken,
        'width': e.width,
        'height': e.height,
        'scanned': 0,
      };

  LocalMediaItem _item(Map<String, Object?> row) {
    final exif = row['exif_json'] as String?;
    return LocalMediaItem(
      id: row['media_id']! as int,
      uri: row['uri']! as String,
      displayName: row['display_name']! as String,
      dateModified: row['date_modified']! as int,
      dateTaken: row['date_taken'] as int?,
      meta: exif == null
          ? null
          : PhotoMeta.fromJson(
              (jsonDecode(exif) as Map).cast<String, Object?>()),
    );
  }
}
