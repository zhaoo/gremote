import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_type.dart';

abstract final class GRemoteTheme {
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);
  static ThemeData get light => _build(AppPalette.light, Brightness.light);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      onError: Colors.white,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: palette.background,
      surfaceContainerLow: palette.raised,
      surfaceContainer: palette.raised,
      surfaceContainerHigh: palette.raised,
      surfaceContainerHighest: palette.divider,
      primaryContainer: palette.raised,
      onPrimaryContainer: palette.text,
      onSurfaceVariant: palette.muted,
      outlineVariant: palette.divider,
      secondary: palette.accent,
      onSecondary: palette.onAccent,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      secondaryContainer: palette.accent,
      onSecondaryContainer: palette.onAccent,
      surface: palette.surface,
      onSurface: palette.text,
      outline: palette.divider,
      error: palette.danger,
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      useMaterial3: true,
      extensions: [palette],
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
            color: palette.text, fontSize: 26, fontWeight: FontWeight.w500),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.raised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      ),
      tabBarTheme: TabBarTheme(
        indicator: const BoxDecoration(),
        dividerColor: Colors.transparent,
        labelColor: palette.text,
        unselectedLabelColor: palette.muted,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      textTheme: base.textTheme.copyWith(
        displaySmall: GRemoteType.display.copyWith(
          color: palette.text,
          fontSize: 36,
        ),
        headlineSmall: GRemoteType.display.copyWith(
          color: palette.text,
          fontSize: 28,
        ),
        bodyLarge: GRemoteType.body.copyWith(color: palette.text),
        bodyMedium: GRemoteType.body.copyWith(color: palette.muted),
        labelLarge: GRemoteType.body.copyWith(fontWeight: FontWeight.w500),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      cardTheme: CardTheme(
        color: palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: palette.divider),
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.divider),
    );
  }
}
