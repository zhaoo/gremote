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
      : _known = initial.loadFailed ? null : initial.preferences,
        super(initial);
  final PreferencesRepository _repository;
  Future<void> _tail = Future.value();
  AppPreferences? _known;
  ThemePreference? _pendingTheme;
  bool? _pendingHaptics;
  int _revision = 0;

  Future<void> setTheme(ThemePreference value) {
    _pendingTheme = value;
    return _save(state.preferences.copyWith(theme: value));
  }

  Future<void> setHaptics(bool value) {
    _pendingHaptics = value;
    return _save(state.preferences.copyWith(haptics: value));
  }

  Future<void> retry() {
    if (_pendingTheme != null || _pendingHaptics != null) {
      return _save(state.preferences);
    }
    final revision = ++_revision;
    state = PreferencesState(
        preferences: state.preferences, saving: true, loadFailed: true);
    return _tail = _tail.then((_) async {
      final loaded = await _repository.hydrate();
      if (!loaded.loadFailed) _known = loaded.preferences;
      if (mounted && revision == _revision) state = loaded;
    });
  }

  Future<void> _save(AppPreferences optimistic) {
    final revision = ++_revision;
    final theme = _pendingTheme, haptics = _pendingHaptics;
    state = PreferencesState(
        preferences: optimistic, saving: true, loadFailed: _known == null);
    // Serialize intent patches. Unknown fields are read successfully before a
    // full snapshot is written; a failed write retains every pending intent.
    return _tail = _tail.then((_) async {
      Object? failure;
      var applied = optimistic;
      try {
        final baseline = _known ?? await _repository.load();
        _known = baseline;
        applied = baseline.copyWith(theme: theme, haptics: haptics);
        await _repository.save(applied);
        _known = applied;
        if (revision == _revision) {
          _pendingTheme = null;
          _pendingHaptics = null;
        }
      } catch (error) {
        failure = error;
      }
      if (mounted && revision == _revision) {
        state = PreferencesState(
            preferences: applied, error: failure, loadFailed: _known == null);
      }
    });
  }
}
