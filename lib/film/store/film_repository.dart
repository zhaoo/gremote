import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../model/camera_photo_identity.dart';
import '../model/film_recipe.dart';
import '../model/film_roll.dart';

class FilmRepository {
  FilmRepository(this.db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final Database db;
  final DateTime Function() _clock;
  String _id() => List.generate(16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
  Future<void> _recipe(DatabaseExecutor tx, FilmRecipe recipe) => tx.insert(
      'film_recipes',
      {
        'fingerprint': recipe.fingerprint,
        'recipe_json': jsonEncode(recipe.toJson()),
        'created_at': _clock().millisecondsSinceEpoch
      },
      conflictAlgorithm: ConflictAlgorithm.ignore);
  Future<FilmRoll> createRoll(
      {required String name,
      required int targetCount,
      required FilmRecipe recipe}) async {
    final clean = name.trim();
    if (clean.isEmpty ||
        clean.runes.length > 24 ||
        targetCount < 1 ||
        targetCount > 999) {
      throw const FormatException('请输入 1–24 字的卷名和 1–999 的计划张数');
    }
    final now = _clock(), id = _id();
    await db.transaction((tx) async {
      if ((await tx.query('film_rolls',
              columns: ['id'], where: 'status = ?', whereArgs: ['open']))
          .isNotEmpty) throw StateError('请先结束当前胶卷');
      await _recipe(tx, recipe);
      await tx.insert('film_rolls', {
        'id': id,
        'name': clean,
        'target_count': targetCount,
        'recipe_fingerprint': recipe.fingerprint,
        'status': 'open',
        'created_at': now.millisecondsSinceEpoch
      });
    });
    return FilmRoll(
        id: id,
        name: clean,
        targetCount: targetCount,
        recipeFingerprint: recipe.fingerprint,
        status: FilmRollStatus.open,
        createdAt: now);
  }

  Future<List<FilmRoll>> rolls() async => [
        for (final row in await db.rawQuery(
            'SELECT r.*, (SELECT COUNT(*) FROM film_roll_items i WHERE i.roll_id=r.id) AS confirmed_count FROM film_rolls r ORDER BY r.created_at DESC, r.id'))
          _roll(row)
      ];
  Future<FilmRoll?> activeRoll() async {
    final rows = await rolls();
    for (final roll in rows) {
      if (roll.status == FilmRollStatus.open) return roll;
    }
    return null;
  }

  Future<FilmRecipe> recipe(String fingerprint) async {
    final rows = await db.query('film_recipes',
        where: 'fingerprint=?', whereArgs: [fingerprint], limit: 1);
    if (rows.isEmpty) throw const FormatException('胶卷配方不存在');
    final recipe = FilmRecipe.fromJson(
        jsonDecode(rows.single['recipe_json'] as String)
            as Map<String, dynamic>);
    if (recipe.fingerprint != fingerprint) {
      throw const FormatException('胶卷配方校验失败');
    }
    return recipe;
  }

  Future<void> closeRoll(String id) async {
    final count = await db.update('film_rolls',
        {'status': 'closed', 'closed_at': _clock().millisecondsSinceEpoch},
        where: 'id=? AND status=?', whereArgs: [id, 'open']);
    if (count == 0) throw StateError('胶卷已结束或不存在');
  }

  Future<RollItem> addConfirmedPhoto(
      {required String rollId,
      required CameraPhotoIdentity identity,
      required FilmRecipe recipe,
      required List<String> files,
      required RecipeConfidence confidence,
      int? mediaId}) async {
    if (!identity.isStable ||
        files.isEmpty ||
        files.any((f) =>
            !RegExp(r'^[A-Za-z0-9_-]+\.(jpe?g|dng)$', caseSensitive: false)
                .hasMatch(f))) throw const FormatException('照片身份尚未确认');
    final result = await db.transaction((tx) async {
      if ((await tx.query('film_rolls',
              columns: ['id'], where: 'id=?', whereArgs: [rollId], limit: 1))
          .isEmpty) throw StateError('胶卷不存在');
      final old = await tx.query('film_roll_items',
          where: 'camera_key=?', whereArgs: [identity.key], limit: 1);
      if (old.isNotEmpty) {
        final row = old.single;
        if (row['roll_id'] != rollId) throw StateError('这张照片已归入其他胶卷');
        final merged = {
          ...(jsonDecode(row['files_json'] as String) as List).cast<String>(),
          ...files
        }.toList()
          ..sort();
        await tx.update(
            'film_roll_items',
            {
              'files_json': jsonEncode(merged),
              if (mediaId != null && row['media_id'] == null)
                'media_id': mediaId
            },
            where: 'id=?',
            whereArgs: [row['id']]);
        return row['id'] as String;
      }
      await _recipe(tx, recipe);
      final id = _id();
      await tx.insert('film_roll_items', {
        'id': id,
        'roll_id': rollId,
        'camera_key': identity.key,
        'identity_json': jsonEncode(identity.toJson()),
        'recipe_fingerprint': recipe.fingerprint,
        'recipe_json': jsonEncode(recipe.toJson()),
        'files_json': jsonEncode(files.toSet().toList()..sort()),
        'confidence': confidence.name,
        'media_id': mediaId,
        'created_at': _clock().millisecondsSinceEpoch,
        'selected': 0
      });
      return id;
    });
    return (await listItems(rollId)).firstWhere((e) => e.id == result);
  }

  Future<List<RollItem>> listItems(String rollId) async => [
        for (final row in await db.query('film_roll_items',
            where: 'roll_id=?',
            whereArgs: [rollId],
            orderBy: 'created_at ASC, id ASC'))
          _item(row)
      ];
  Future<void> setSelected(String itemId, bool selected) =>
      db.update('film_roll_items', {'selected': selected ? 1 : 0},
          where: 'id=?', whereArgs: [itemId]);
  static FilmRoll _roll(Map<String, Object?> row) => FilmRoll(
      id: row['id'] as String,
      name: row['name'] as String,
      targetCount: row['target_count'] as int,
      recipeFingerprint: row['recipe_fingerprint'] as String,
      status: FilmRollStatus.values.byName(row['status'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      closedAt: row['closed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['closed_at'] as int),
      confirmedCount: row['confirmed_count'] as int? ?? 0);
  static RollItem _item(Map<String, Object?> row) {
    final recipe = FilmRecipe.fromJson(
        jsonDecode(row['recipe_json'] as String) as Map<String, dynamic>);
    if (recipe.fingerprint != row['recipe_fingerprint']) {
      throw const FormatException('照片配方校验失败');
    }
    return RollItem(
        id: row['id'] as String,
        rollId: row['roll_id'] as String,
        identity: CameraPhotoIdentity.fromJson(
            jsonDecode(row['identity_json'] as String) as Map<String, dynamic>),
        recipe: recipe,
        files: (jsonDecode(row['files_json'] as String) as List).cast<String>(),
        confidence: RecipeConfidence.values.byName(row['confidence'] as String),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        mediaId: row['media_id'] as int?,
        selected: row['selected'] == 1);
  }
}
