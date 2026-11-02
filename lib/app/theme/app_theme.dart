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
      appBarTheme: const AppBarTheme(
        backgroundColor: GRemoteColors.night,
        foregroundColor: GRemoteColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        titleTextStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: GRemoteColors.raised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      ),
      tabBarTheme: const TabBarTheme(
        indicator: BoxDecoration(),
        dividerColor: Colors.transparent,
        labelColor: GRemoteColors.text,
        unselectedLabelColor: GRemoteColors.muted,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
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
        labelLarge: GRemoteType.body.copyWith(fontWeight: FontWeight.w500),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GRemoteColors.gold,
          foregroundColor: GRemoteColors.night,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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
