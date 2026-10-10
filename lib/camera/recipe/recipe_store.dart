import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sqflite/sqflite.dart';

import '../../darkroom/darkroom_providers.dart';
import '../capture/capture_tracker.dart';
import 'combo_recipe.dart';

@immutable
class CaptureTag {
  const CaptureTag({
    required this.id,
    required this.baseName,
    required this.dir,
    required this.wallSeconds,
    required this.timeSource,
    required this.recipeId,
    required this.confirmed,
    this.effect,
    this.programRunId,
  });

  final int id;
  final String baseName;
  final String dir;
  final int wallSeconds;
  final TimeSource timeSource;
  final String recipeId;
  final String? effect;
  final String? programRunId;
  final bool confirmed;
}

final recipeStoreProvider =
    Provider<RecipeStore>((ref) => RecipeStore(ref.watch(databaseProvider)));

final comboRecipesProvider = FutureProvider<List<ComboRecipe>>(
  (ref) => ref.watch(recipeStoreProvider).recipes(),
);

class RecipeStore {
  RecipeStore(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;
  var _sequence = 0;

  Future<List<ComboRecipe>> recipes() async => [
        for (final row in await _db.query(
          'combo_recipes',
          orderBy: 'sort ASC, created_at ASC',
        ))
          _recipe(row),
      ];

  Future<ComboRecipe> create({
    required String name,
    String? effect,
    String? exportPresetId,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 24) {
      throw ArgumentError.value(name, 'name', 'must contain 1–24 characters');
    }
    final max = await _db
        .rawQuery('SELECT COALESCE(MAX(sort), -1) AS value FROM combo_recipes');
    final sort = (max.single['value'] as int) + 1;
    final created = _clock();
    final id = 'recipe-${created.microsecondsSinceEpoch}-${_sequence++}';
    final recipe = ComboRecipe(
      id: id,
      name: cleanName,
      effect: effect,
      exportPresetId: exportPresetId,
      sort: sort,
      createdAt: created,
    );
    await _db.insert('combo_recipes', _recipeRow(recipe));
    return recipe;
  }

  /// Tags deliberately survive recipe deletion as a historical record.
  Future<void> delete(String id) async {
    if (id == ComboRecipe.factory.id) return;
    await _db.delete('combo_recipes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addTag(CaptureRecord record, String recipeId) async {
    if (recipeId == ComboRecipe.factory.id) return;
    await _db.insert('capture_tags', {
      'base_name': record.baseName.toUpperCase(),
      'dir': record.dir,
      'captured_at': record.wallSeconds,
      'time_source': record.timeSource.name,
      'combo_recipe_id': recipeId,
      'effect': record.effect,
      'program_run_id': record.programRunId,
      'confirmed': 0,
      'created_at': _clock().millisecondsSinceEpoch ~/ 1000,
    });
  }

  Future<List<CaptureTag>> tagsForBaseNames(Iterable<String> names) async {
    final normalized = names.map((n) => n.toUpperCase()).toSet().toList();
    if (normalized.isEmpty) return const [];
    final marks = List.filled(normalized.length, '?').join(',');
    final rows = await _db.query(
      'capture_tags',
      where: 'UPPER(base_name) IN ($marks)',
      whereArgs: normalized,
      orderBy: 'captured_at DESC',
    );
    return [for (final row in rows) _tag(row)];
  }

  Future<void> confirmTag(int id) => _db.update(
        'capture_tags',
        {'confirmed': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> saveRun(Map<String, Object?> run) =>
      _db.transaction((txn) async {
        await txn.insert(
          'program_runs',
          {
            'id': run['id'],
            'kind': run['kind'],
            'config_json': jsonEncode(run['config'] ?? const {}),
            'state': run['state'],
            'frames_done': run['done'] ?? 0,
            'started_at': run['startedAt'],
            'ended_at': run['endedAt'],
            'log_json': jsonEncode(run['log'] ?? const []),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.rawDelete('''
          DELETE FROM program_runs WHERE id IN (
            SELECT id FROM program_runs
            ORDER BY started_at DESC, id DESC
            LIMIT -1 OFFSET 50
          )''');
      });

  static ComboRecipe _recipe(Map<String, Object?> row) => ComboRecipe(
        id: row['id']! as String,
        name: row['name']! as String,
        effect: row['effect'] as String?,
        exportPresetId: row['export_preset_id'] as String?,
        sort: row['sort']! as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at']! as int,
          isUtc: true,
        ),
      );

  static CaptureTag _tag(Map<String, Object?> row) => CaptureTag(
        id: row['id']! as int,
        baseName: row['base_name']! as String,
        dir: row['dir']! as String,
        wallSeconds: row['captured_at']! as int,
        timeSource: TimeSource.values.firstWhere(
          (value) => value.name == row['time_source'],
          orElse: () => TimeSource.phone,
        ),
        recipeId: row['combo_recipe_id']! as String,
        effect: row['effect'] as String?,
        programRunId: row['program_run_id'] as String?,
        confirmed: row['confirmed'] == 1,
      );

  static Map<String, Object?> _recipeRow(ComboRecipe recipe) => {
        'id': recipe.id,
        'name': recipe.name,
        'effect': recipe.effect,
        'export_preset_id': recipe.exportPresetId,
        'sort': recipe.sort,
        'created_at': recipe.createdAt.millisecondsSinceEpoch,
      };
}
