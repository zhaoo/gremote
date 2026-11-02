import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'home_cover_settings.dart';

class HomeCoverRepository {
  HomeCoverRepository(this.db);
  final Database db;
  static const key = 'home.cover.v1';
  Future<HomeCoverSettings> load() async {
    final rows =
        await db.query('app_kv', where: 'key=?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return const HomeCoverSettings();
    try {
      return HomeCoverSettings.fromJson(Map<String, dynamic>.from(
          jsonDecode(rows.single['value']! as String) as Map));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('封面配置读取失败');
    }
  }

  Future<void> save(HomeCoverSettings value) async {
    final checked = HomeCoverSettings.fromJson(value.toJson());
    await db.insert(
        'app_kv', {'key': key, 'value': jsonEncode(checked.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
