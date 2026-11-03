import 'package:sqflite/sqflite.dart';

import 'app_preferences.dart';

class PreferencesRepository {
  PreferencesRepository(this.db);
  final Database db;

  Future<AppPreferences> load() async {
    final rows = await db.query('app_kv',
        where: 'key IN (?, ?)',
        whereArgs: ['settings.appearance', 'settings.haptics']);
    final values = {for (final row in rows) row['key']: row['value']};
    return AppPreferences(
      theme: ThemePreference.values.firstWhere(
        (value) => value.name == values['settings.appearance'],
        orElse: () => ThemePreference.dark,
      ),
      haptics: values['settings.haptics'] != 'false',
    );
  }

  Future<void> save(AppPreferences preferences) => db.transaction((txn) async {
        await txn.insert('app_kv',
            {'key': 'settings.appearance', 'value': preferences.theme.name},
            conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert(
            'app_kv',
            {
              'key': 'settings.haptics',
              'value': preferences.haptics.toString()
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

  Future<PreferencesState> hydrate() async {
    try {
      return PreferencesState(preferences: await load());
    } catch (error) {
      return PreferencesState(error: error);
    }
  }
}
