import 'package:flutter/material.dart';

enum ThemePreference {
  dark,
  light,
  system;

  ThemeMode get themeMode => switch (this) {
        dark => ThemeMode.dark,
        light => ThemeMode.light,
        system => ThemeMode.system,
      };
}

@immutable
class AppPreferences {
  const AppPreferences(
      {this.theme = ThemePreference.dark, this.haptics = true});
  final ThemePreference theme;
  final bool haptics;

  AppPreferences copyWith({ThemePreference? theme, bool? haptics}) =>
      AppPreferences(
          theme: theme ?? this.theme, haptics: haptics ?? this.haptics);
}

@immutable
class PreferencesState {
  const PreferencesState({
    this.preferences = const AppPreferences(),
    this.saving = false,
    this.error,
    this.loadFailed = false,
  });
  final AppPreferences preferences;
  final bool saving;
  final Object? error;
  final bool loadFailed;
}
