import 'dart:convert';
import '../../camera/companion/camera_film_catalog.dart';
import 'package:sqflite/sqflite.dart';
import '../model/film_recipe.dart' show canonicalJson;

/// Keeps the original wire snapshot, including newer read-only fields.
class SyncRepository {
  SyncRepository(this.db);
  final Database db;
  Future<void> saveCameraRecipe(CameraFilmRecipe recipe) async {
    await db.insert(
        'camera_film_recipes',
        {
          'fingerprint': recipe.fingerprint,
          'recipe_json': jsonEncode(recipe.toJson()),
          'created_at': DateTime.now().millisecondsSinceEpoch
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<CameraFilmRecipe>> cameraRecipes() async =>
      (await db.query('camera_film_recipes',
              orderBy: 'created_at DESC', limit: 100))
          .map((row) {
        final recipe = CameraFilmRecipe.fromJson(
            jsonDecode(row['recipe_json'] as String) as Map<String, dynamic>);
        if (recipe.fingerprint != row['fingerprint']) {
          throw const FormatException('相机配方校验失败');
        }
        return recipe;
      }).toList();

  Future<void> saveBaseline(
      String instanceId, Map<String, Object?> snapshot) async {
    if (instanceId.isEmpty ||
        snapshot['bootId'] is! String ||
        snapshot['revision'] is! String) {
      throw const FormatException('相机状态身份缺失');
    }
    await db.insert(
        'camera_sync_baselines',
        {
          'instance_id': instanceId,
          'snapshot_json': jsonEncode(snapshot),
          'updated_at': DateTime.now().millisecondsSinceEpoch
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> baseline(String instanceId) async {
    final rows = await db.query('camera_sync_baselines',
        where: 'instance_id=?', whereArgs: [instanceId], limit: 1);
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['snapshot_json'] as String)
            as Map<String, dynamic>;
  }

  Future<void> saveOperation(
      {required String requestId,
      required String instanceId,
      required Map<String, Object?> payload,
      required String status}) async {
    if (requestId.isEmpty || instanceId.isEmpty) {
      throw const FormatException('同步操作身份缺失');
    }
    await db.transaction((tx) async {
      final rows = await tx.query('camera_sync_operations',
          where: 'request_id=?', whereArgs: [requestId], limit: 1);
      final encoded = canonicalJson(payload);
      if (rows.isNotEmpty &&
          (rows.single['instance_id'] != instanceId ||
              canonicalJson(
                      jsonDecode(rows.single['payload_json'] as String)) !=
                  encoded)) {
        throw StateError('同步操作身份不可复用');
      }
      await tx.insert(
          'camera_sync_operations',
          {
            'request_id': requestId,
            'instance_id': instanceId,
            'payload_json': encoded,
            'status': status,
            'updated_at': DateTime.now().millisecondsSinceEpoch
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, Object?>>> unresolved(String instanceId) =>
      db.query('camera_sync_operations',
          where: 'instance_id=? AND status IN (?,?,?,?)',
          whereArgs: [instanceId, 'queued', 'applying', 'verifying', 'unknown'],
          orderBy: 'updated_at');
}
