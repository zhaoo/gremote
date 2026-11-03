import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../darkroom/darkroom_providers.dart';
import 'app_preferences.dart';
import 'preferences_repository.dart';

/// Bootstrap overrides the seed before the first routed frame.
final initialPreferencesProvider =
    Provider<PreferencesState>((ref) => const PreferencesState());
final preferencesRepositoryProvider = Provider<PreferencesRepository>(
    (ref) => PreferencesRepository(ref.watch(databaseProvider)));
final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, PreferencesState>((ref) =>
        AppPreferencesController(ref.watch(preferencesRepositoryProvider),
            ref.watch(initialPreferencesProvider)));

class AppPreferencesController extends StateNotifier<PreferencesState> {
  AppPreferencesController(this._repository, PreferencesState initial)
      : super(initial);
  final PreferencesRepository _repository;
  Future<void> _tail = Future.value();
  int _revision = 0;

  Future<void> setTheme(ThemePreference value) =>
      _save(state.preferences.copyWith(theme: value));
  Future<void> setHaptics(bool value) =>
      _save(state.preferences.copyWith(haptics: value));
  Future<void> retry() => _save(state.preferences);

  Future<void> _save(AppPreferences preferences) {
    final revision = ++_revision;
    state = PreferencesState(preferences: preferences, saving: true);
    // Serialize snapshots: an older disk write may never finish after a newer one.
    return _tail = _tail.then((_) async {
      Object? failure;
      try {
        await _repository.save(preferences);
      } catch (error) {
        failure = error;
      }
      if (mounted && revision == _revision) {
        state = PreferencesState(preferences: preferences, error: failure);
      }
    });
  }
}
