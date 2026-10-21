import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// Keeps the original wire snapshot, including newer read-only fields.
class SyncRepository {
  SyncRepository(this.db);
  final Database db;
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
      final encoded = jsonEncode(payload);
      if (rows.isNotEmpty &&
          (rows.single['instance_id'] != instanceId ||
              rows.single['payload_json'] != encoded)) {
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
