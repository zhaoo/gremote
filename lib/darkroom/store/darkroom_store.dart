import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:sqflite/sqflite.dart';

import '../model/edit_document.dart';
import '../model/export_recipe.dart';

@immutable
class ExportPreset {
  const ExportPreset({
    required this.id,
    required this.name,
    required this.recipe,
    required this.createdAt,
  });

  final String id;
  final String name;
  final ExportRecipe recipe;
  final DateTime createdAt;
}

@immutable
class ImportedLut {
  const ImportedLut({
    required this.id,
    required this.name,
    required this.size,
    required this.sha256,
    required this.filePath,
  });

  final String id;
  final String name;
  final int size;
  final String sha256;
  final String filePath;
}

/// Persists darkroom edits, export presets and imported LUT records.
class DarkroomStore {
  DarkroomStore(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  static List<String> _ids(Object? raw) {
    if (raw == null) return [];
    final value = jsonDecode(raw as String);
    if (value is! List || value.any((id) => id is! String)) {
      throw const FormatException('invalid LUT collection');
    }
    return value.cast<String>().toSet().toList();
  }

  Future<(List<String>, Set<String>)> lutCollections() async {
    final rows = await _db.query('app_kv',
        where: 'key IN (?, ?)',
        whereArgs: ['studio.lut.recent', 'studio.lut.favorites']);
    final values = {for (final row in rows) row['key']: row['value']};
    return (
      _ids(values['studio.lut.recent']),
      _ids(values['studio.lut.favorites']).toSet()
    );
  }

  Future<void> _updateLutIds(String key, void Function(List<String>) update) =>
      _db.transaction((txn) async {
        final rows = await txn.query('app_kv',
            where: 'key = ?', whereArgs: [key], limit: 1);
        final ids = _ids(rows.isEmpty ? null : rows.single['value']);
        update(ids);
        await txn.insert('app_kv', {'key': key, 'value': jsonEncode(ids)},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
  Future<void> toggleLutFavorite(String id) =>
      _updateLutIds('studio.lut.favorites', (ids) {
        if (!ids.remove(id)) ids.add(id);
      });
  Future<void> rememberLut(String id) =>
      _updateLutIds('studio.lut.recent', (ids) {
        ids.remove(id);
        ids.insert(0, id);
        if (ids.length > 24) ids.removeRange(24, ids.length);
      });

  Future<EditDocument?> loadEdit(int mediaId) async {
    final rows = await _db.query('edit_documents',
        where: 'media_id = ?', whereArgs: [mediaId], limit: 1);
    return rows.isEmpty ? null : _edit(rows.single);
  }

  Future<void> saveEdit(EditDocument doc) => _db.insert(
        'edit_documents',
        {
          'media_id': doc.mediaId,
          'recipe_json': doc.recipeJson,
          'title': doc.title,
          'location': doc.location,
          'hidden_fields_json': doc.hiddenJson,
          'updated_at': doc.updatedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<EditDocument>> recentEdits({int limit = 20}) async {
    final rows = await _db.query('edit_documents',
        orderBy: 'updated_at DESC', limit: limit);
    return rows.map(_edit).toList();
  }

  Future<List<ExportPreset>> presets() async {
    final rows = await _db.query('export_presets', orderBy: 'created_at DESC');
    return rows
        .map((row) => ExportPreset(
              id: row['id']! as String,
              name: row['name']! as String,
              recipe: ExportRecipe.fromJson(
                  (jsonDecode(row['recipe_json']! as String) as Map)
                      .cast<String, Object?>()),
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                  row['created_at']! as int),
            ))
        .toList();
  }

  Future<ExportPreset> savePreset(String name, ExportRecipe recipe) async {
    final now = _clock();
    final preset = ExportPreset(
      id: 'preset:${now.microsecondsSinceEpoch.toRadixString(36)}',
      name: name,
      recipe: recipe,
      createdAt: now,
    );
    await _db.insert('export_presets', {
      'id': preset.id,
      'name': name,
      'recipe_json': jsonEncode(recipe.toJson()),
      'created_at': now.millisecondsSinceEpoch,
    });
    return preset;
  }

  Future<void> renamePreset(String id, String name) =>
      _db.update('export_presets', {'name': name},
          where: 'id = ?', whereArgs: [id]);

  Future<void> deletePreset(String id) =>
      _db.delete('export_presets', where: 'id = ?', whereArgs: [id]);

  Future<List<ImportedLut>> importedLuts() async {
    final rows = await _db.query('luts',
        where: 'source = ?', whereArgs: ['imported'], orderBy: 'created_at');
    return rows.map(_lut).toList();
  }

  /// Returns the existing record when the same file was imported before.
  Future<ImportedLut> addImportedLut({
    required String name,
    required int size,
    required String sha256,
    required String filePath,
  }) async {
    final existing = await _db.query('luts',
        where: 'sha256 = ?', whereArgs: [sha256], limit: 1);
    if (existing.isNotEmpty) return _lut(existing.single);
    final lut = ImportedLut(
      id: 'imported:${sha256.substring(0, sha256.length < 16 ? sha256.length : 16)}',
      name: name,
      size: size,
      sha256: sha256,
      filePath: filePath,
    );
    await _db.insert('luts', {
      'id': lut.id,
      'name': name,
      'source': 'imported',
      'size': size,
      'file_path': filePath,
      'sha256': sha256,
      'created_at': _clock().millisecondsSinceEpoch,
    });
    return lut;
  }

  Future<void> deleteLut(String id) =>
      _db.delete('luts', where: 'id = ?', whereArgs: [id]);

  EditDocument _edit(Map<String, Object?> row) => EditDocument.fromJsonParts(
        mediaId: row['media_id']! as int,
        recipeJson: row['recipe_json']! as String,
        title: row['title']! as String,
        location: row['location']! as String,
        hiddenJson: row['hidden_fields_json']! as String,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      );

  ImportedLut _lut(Map<String, Object?> row) => ImportedLut(
        id: row['id']! as String,
        name: row['name']! as String,
        size: row['size']! as int,
        sha256: row['sha256']! as String,
        filePath: row['file_path']! as String,
      );
}
