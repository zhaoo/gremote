import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../../camera/http/camera_files.dart';
import '../model/camera_photo_identity.dart';
import '../model/camera_roll_frame.dart';
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
  Future<void> saveRecipe(FilmRecipe recipe) => _recipe(db, recipe);
  Future<List<FilmRecipe>> savedRecipes() async =>
      (await db.query('film_recipes', orderBy: 'created_at DESC', limit: 100))
          .map((row) => FilmRecipe.fromJson(
              jsonDecode(row['recipe_json'] as String) as Map<String, dynamic>))
          .toList();
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

  /// Removes App grouping only. MediaStore, SD files and recipes are untouched.
  Future<void> deleteRollArchive(String id) => db.transaction((tx) async {
        await tx.delete('film_roll_items', where: 'roll_id=?', whereArgs: [id]);
        await tx.delete('film_rolls', where: 'id=?', whereArgs: [id]);
      });

  String _hiddenCameraRollKey(String cameraKey) {
    if (cameraKey.isEmpty || cameraKey.length > 256)
      throw const FormatException('相机身份尚未读取');
    return 'camera.roll.hidden.${sha256.convert(utf8.encode(cameraKey))}';
  }

  Set<String> _hiddenRollIds(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return {};
    final value = jsonDecode(rows.single['value'] as String);
    if (value is! List ||
        value.any(
            (id) => id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)))
      throw const FormatException('胶卷记录读取失败');
    return value.cast<String>().toSet();
  }

  Future<Set<String>> hiddenCameraRolls(String cameraKey) async =>
      _hiddenRollIds(await db.query('app_kv',
          where: 'key=?',
          whereArgs: [_hiddenCameraRollKey(cameraKey)],
          limit: 1));

  /// Local visibility preference, never a camera journal mutation.
  Future<void> hideCameraRoll(String cameraKey, String rollId) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(rollId))
      throw const FormatException('胶卷记录无效');
    final key = _hiddenCameraRollKey(cameraKey);
    await db.transaction((tx) async {
      final ids = _hiddenRollIds(
          await tx.query('app_kv', where: 'key=?', whereArgs: [key], limit: 1))
        ..add(rollId);
      await tx.insert(
          'app_kv', {'key': key, 'value': jsonEncode(ids.toList()..sort())},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<RollItem> addConfirmedPhoto(
      {required String rollId,
      required CameraPhotoIdentity identity,
      required FilmRecipe recipe,
      required List<String> files,
      required RecipeConfidence confidence,
      int? mediaId,
      bool Function()? isCurrent}) async {
    if (!identity.isStable ||
        files.isEmpty ||
        files.any((f) =>
            !RegExp(r'^[A-Za-z0-9_-]+\.(jpe?g|dng)$', caseSensitive: false)
                .hasMatch(f))) throw const FormatException('照片身份尚未确认');
    final result = await db.transaction((tx) async {
      if (isCurrent != null && !isCurrent()) throw StateError('拍摄会话已改变');
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
              if (mediaId != null &&
                  (row['media_id'] == null ||
                      identity.instanceId == 'local-photo'))
                'media_id': mediaId
            },
            where: 'id=?',
            whereArgs: [row['id']]);
        if (isCurrent != null && !isCurrent()) throw StateError('拍摄会话已改变');
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
      if (isCurrent != null && !isCurrent()) throw StateError('拍摄会话已改变');
      return id;
    });
    return (await listItems(rollId)).firstWhere((e) => e.id == result);
  }

  Future<RollItem> importCameraFrame(CameraFile file, CameraRollFrame frame,
      {required String hash, int? mediaId, FilmRecipe? recipe}) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(file.dir) ||
        !RegExp(r'^[A-Za-z0-9_-]+\.(jpe?g|dng)$', caseSensitive: false)
            .hasMatch(file.file)) {
      throw const FormatException('机身胶卷原片校验失败');
    }
    final identity = CameraPhotoIdentity(
        instanceId: 'm10r',
        storageId: 'camera-roll',
        storageEpoch: frame.rollId,
        dir: file.dir,
        baseName: file.baseName,
        captureId: frame.number.toString());
    final format = file.extension == 'DNG' ? 'DNG' : 'JPEG';
    final now = _clock().millisecondsSinceEpoch;
    return db.transaction((tx) async {
      final rolls = await tx.query('film_rolls',
          columns: ['target_count'], where: 'id=?', whereArgs: [frame.rollId]);
      if (rolls.isEmpty) {
        await tx.insert('film_rolls', {
          'id': frame.rollId,
          'name': '机身胶卷 ${frame.rollId.substring(0, 8)}',
          'target_count': frame.targetCount,
          'recipe_fingerprint': '',
          'status': FilmRollStatus.archived.name,
          'created_at': now
        });
      } else if (rolls.single['target_count'] != frame.targetCount) {
        throw StateError('机身胶卷计划张数与现有记录不一致');
      }

      final rows = await tx.query('film_roll_items',
          where: 'roll_id=? AND frame_number=?',
          whereArgs: [frame.rollId, frame.number]);
      final old = rows.singleOrNull;
      final hashes = _originalHashes(old?['original_hashes']);
      final oldIdentity = old == null
          ? null
          : CameraPhotoIdentity.fromJson(
              jsonDecode(old['identity_json'] as String)
                  as Map<String, dynamic>);
      final fromCamera = file.dir != localCameraRollDirectory;
      final confirmCameraPath =
          fromCamera && oldIdentity?.dir == localCameraRollDirectory;
      if (old != null &&
          (fromCamera &&
                  !confirmCameraPath &&
                  old['camera_key'] != identity.key ||
              hashes[format] != null && hashes[format] != hash ||
              recipe != null &&
                  old['recipe_fingerprint'] != '' &&
                  old['recipe_fingerprint'] != recipe.fingerprint)) {
        throw StateError('机身胶卷的同一帧有不同的原片或配方');
      }
      hashes[format] = hash;
      final existing = old == null ? <String>[] : _files(old['files_json']);
      final id = old?['id'] as String? ?? _id();
      final attachPreview = mediaId != null &&
          (format == 'JPEG' || old?['preview_format'] != 'JPEG');
      final values = <String, Object?>{
        'original_hashes': jsonEncode(hashes),
        'files_json': jsonEncode({...existing, file.file}.toList()..sort()),
        if (attachPreview) 'media_id': mediaId,
        if (attachPreview) 'preview_format': format,
        if (confirmCameraPath) 'camera_key': identity.key,
        if (confirmCameraPath) 'identity_json': jsonEncode(identity.toJson()),
      };
      if (recipe != null) {
        await _recipe(tx, recipe);
        values.addAll({
          'recipe_fingerprint': recipe.fingerprint,
          'recipe_json': jsonEncode(recipe.toJson()),
          'confidence': RecipeConfidence.cameraConfirmed.name,
        });
      }
      if (old == null) {
        await tx.insert('film_roll_items', {
          'id': id,
          'roll_id': frame.rollId,
          'frame_number': frame.number,
          'camera_key': identity.key,
          'identity_json': jsonEncode(identity.toJson()),
          'recipe_fingerprint': '',
          'recipe_json': 'null',
          'confidence': RecipeConfidence.unverified.name,
          'created_at': now,
          ...values
        });
      } else {
        await tx
            .update('film_roll_items', values, where: 'id=?', whereArgs: [id]);
      }
      final result =
          await tx.query('film_roll_items', where: 'id=?', whereArgs: [id]);
      return _item(result.single);
    });
  }

  Future<List<RollItem>> listItems(String rollId) async => [
        for (final row in await db.query('film_roll_items',
            where: 'roll_id=?',
            whereArgs: [rollId],
            orderBy: 'frame_number IS NULL, frame_number, created_at, id'))
          _item(row)
      ];
  Future<void> setSelected(String itemId, bool selected) =>
      db.update('film_roll_items', {'selected': selected ? 1 : 0},
          where: 'id=?', whereArgs: [itemId]);
  static FilmRoll _roll(Map<String, Object?> row) => FilmRoll(
      id: row['id'] as String,
      name: row['name'] as String,
      targetCount: row['target_count'] as int,
      recipeFingerprint: _recipeFingerprint(row['recipe_fingerprint']),
      status: FilmRollStatus.values.byName(row['status'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      closedAt: row['closed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['closed_at'] as int),
      confirmedCount: row['confirmed_count'] as int? ?? 0);
  static RollItem _item(Map<String, Object?> row) {
    final fingerprint = _recipeFingerprint(row['recipe_fingerprint']);
    final recipe = fingerprint == null
        ? null
        : FilmRecipe.fromJson(
            jsonDecode(row['recipe_json'] as String) as Map<String, dynamic>);
    if (recipe?.fingerprint != fingerprint) {
      throw const FormatException('照片配方校验失败');
    }
    return RollItem(
        id: row['id'] as String,
        rollId: row['roll_id'] as String,
        identity: CameraPhotoIdentity.fromJson(
            jsonDecode(row['identity_json'] as String) as Map<String, dynamic>),
        recipe: recipe,
        files: _files(row['files_json']),
        confidence: RecipeConfidence.values.byName(row['confidence'] as String),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        mediaId: row['media_id'] as int?,
        frameNumber: row['frame_number'] as int?,
        previewHash:
            _originalHashes(row['original_hashes'])[row['preview_format']],
        selected: row['selected'] == 1);
  }

  static String? _recipeFingerprint(Object? stored) =>
      stored is String && stored.isNotEmpty ? stored : null;

  static List<String> _files(Object? stored) =>
      (jsonDecode(stored as String) as List).cast<String>();

  static Map<String, String> _originalHashes(Object? stored) => stored == null
      ? {}
      : (jsonDecode(stored as String) as Map<String, dynamic>)
          .cast<String, String>();
}
