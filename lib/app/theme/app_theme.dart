import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_type.dart';

abstract final class GRemoteTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: GRemoteColors.gold,
      onPrimary: GRemoteColors.night,
      secondaryContainer: GRemoteColors.gold,
      onSecondaryContainer: GRemoteColors.night,
      surface: GRemoteColors.navy,
      onSurface: GRemoteColors.text,
      outline: GRemoteColors.divider,
      error: GRemoteColors.danger,
    );

    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: GRemoteColors.night,
      useMaterial3: true,
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: GRemoteType.display.copyWith(
          color: GRemoteColors.text,
          fontSize: 36,
        ),
        headlineSmall: GRemoteType.display.copyWith(
          color: GRemoteColors.text,
          fontSize: 28,
        ),
        bodyLarge: GRemoteType.body.copyWith(color: GRemoteColors.text),
        bodyMedium: GRemoteType.body.copyWith(color: GRemoteColors.muted),
        labelLarge: GRemoteType.body.copyWith(fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GRemoteColors.gold,
          foregroundColor: GRemoteColors.night,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: const CardTheme(
        color: GRemoteColors.navy,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: GRemoteColors.divider),
        ),
      ),
      dividerTheme: const DividerThemeData(color: GRemoteColors.divider),
    );
  }
}
