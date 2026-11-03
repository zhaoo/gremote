import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/settings/app_preferences.dart';
import 'package:gremote/settings/preferences_controller.dart';
import 'package:gremote/settings/preferences_repository.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  setUp(() async {
    sqfliteFfiInit();
    db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  test(
      'missing or malformed preferences retain the established dark appearance',
      () async {
    final repository = PreferencesRepository(db);
    expect((await repository.load()).theme, ThemePreference.dark);
    expect((await repository.load()).haptics, isTrue);
    await db
        .insert('app_kv', {'key': 'settings.appearance', 'value': 'unknown'});
    await db.insert('app_kv', {'key': 'settings.haptics', 'value': 'broken'});
    expect((await repository.load()).theme, ThemePreference.dark);
    expect((await repository.load()).haptics, isTrue);
  });

  test(
      'preferences survive reopening a repository without modifying other settings',
      () async {
    await db.insert('app_kv', {'key': 'camera.pending', 'value': 'untouched'});
    await PreferencesRepository(db).save(
        const AppPreferences(theme: ThemePreference.system, haptics: false));
    final loaded = await PreferencesRepository(db).load();
    expect(loaded.theme, ThemePreference.system);
    expect(loaded.haptics, isFalse);
    expect(
        (await db.query('app_kv',
                where: 'key = ?', whereArgs: ['camera.pending']))
            .single['value'],
        'untouched');
  });

  test('rapid selections persist in order and only the newest selection wins',
      () async {
    final gate = Completer<void>();
    final repository = _DelayedRepository(db, gate.future);
    final controller =
        AppPreferencesController(repository, const PreferencesState());
    addTearDown(controller.dispose);
    final first = controller.setTheme(ThemePreference.light);
    final second = controller.setTheme(ThemePreference.system);
    final third = controller.setHaptics(false);
    expect(controller.state.preferences.theme, ThemePreference.system);
    expect(controller.state.saving, isTrue);
    gate.complete();
    await Future.wait([first, second, third]);
    final saved = await PreferencesRepository(db).load();
    expect(saved.theme, ThemePreference.system);
    expect(saved.haptics, isFalse);
    expect(controller.state.saving, isFalse);
    expect(controller.state.error, isNull);
  });

  test('startup read failure retries loading without overwriting a saved theme',
      () async {
    await PreferencesRepository(db).save(
        const AppPreferences(theme: ThemePreference.light, haptics: false));
    final repository = _ReadFailsOnce(db);
    final initial = await repository.hydrate();
    expect(initial.error, isNotNull);
    final controller = AppPreferencesController(repository, initial);
    addTearDown(controller.dispose);
    await controller.retry();
    expect(controller.state.preferences.theme, ThemePreference.light);
    expect(controller.state.preferences.haptics, isFalse);
    expect(
        (await PreferencesRepository(db).load()).theme, ThemePreference.light);
  });

  test('changing haptics after startup read failure preserves saved appearance',
      () async {
    await PreferencesRepository(db).save(
        const AppPreferences(theme: ThemePreference.light, haptics: false));
    final repository = _ReadFailsOnce(db);
    final controller =
        AppPreferencesController(repository, await repository.hydrate());
    addTearDown(controller.dispose);
    await controller.setHaptics(true);
    expect((await repository.load()).theme, ThemePreference.light);
    expect(controller.state.preferences.theme, ThemePreference.light);
  });

  test('pending theme survives failed save followed by another preference',
      () async {
    final controller = AppPreferencesController(
        PreferencesRepository(db), const PreferencesState());
    addTearDown(controller.dispose);
    await db.execute(
        "CREATE TRIGGER reject_settings BEFORE INSERT ON app_kv WHEN NEW.key LIKE 'settings.%' BEGIN SELECT RAISE(ABORT, 'disk unavailable'); END");
    await controller.setTheme(ThemePreference.light);
    await db.execute('DROP TRIGGER reject_settings');
    await controller.setHaptics(false);
    final saved = await PreferencesRepository(db).load();
    expect(saved.theme, ThemePreference.light);
    expect(saved.haptics, isFalse);
  });

  test('failed transaction is visible, preserves unrelated keys and can retry',
      () async {
    await db.insert('app_kv', {'key': 'camera.pending', 'value': 'untouched'});
    await db.execute(
        "CREATE TRIGGER reject_settings BEFORE INSERT ON app_kv WHEN NEW.key LIKE 'settings.%' BEGIN SELECT RAISE(ABORT, 'disk unavailable'); END");
    final controller = AppPreferencesController(
        PreferencesRepository(db), const PreferencesState());
    addTearDown(controller.dispose);
    await controller.setTheme(ThemePreference.light);
    expect(controller.state.preferences.theme, ThemePreference.light);
    expect(controller.state.error, isNotNull);
    expect(controller.state.saving, isFalse);
    expect(
        (await PreferencesRepository(db).load()).theme, ThemePreference.dark);
    await db.execute('DROP TRIGGER reject_settings');
    await controller.retry();
    expect(controller.state.error, isNull);
    expect(
        (await PreferencesRepository(db).load()).theme, ThemePreference.light);
    expect(
        (await db.query('app_kv',
                where: 'key = ?', whereArgs: ['camera.pending']))
            .single['value'],
        'untouched');
  });
}

class _DelayedRepository extends PreferencesRepository {
  _DelayedRepository(super.db, this.gate);
  final Future<void> gate;
  @override
  Future<void> save(AppPreferences preferences) async {
    await gate;
    await super.save(preferences);
  }
}

class _ReadFailsOnce extends PreferencesRepository {
  _ReadFailsOnce(super.db);
  bool first = true;
  @override
  Future<AppPreferences> load() async {
    if (first) {
      first = false;
      throw StateError('read unavailable');
    }
    return super.load();
  }
}
