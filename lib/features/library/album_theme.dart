import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

/// Approved album palette and compact corners are scoped to album surfaces.
ThemeData albumTheme(BuildContext context) {
  final base = Theme.of(context);
  if (base.brightness != Brightness.dark) return base;
  final palette = context.palette.copyWith(
    background: const Color(0xFF161B1B),
    surface: const Color(0xFF161B1B),
    raised: const Color(0xFF252E2C),
    text: const Color(0xFFF2F3ED),
    muted: const Color(0xFFA0AEAA),
    divider: const Color(0xFF35403D),
    accent: const Color(0xFFD7DFC9),
    onAccent: const Color(0xFF24342D),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
  return base.copyWith(
    extensions: [palette],
    scaffoldBackgroundColor: palette.background,
    textTheme: base.textTheme
        .apply(bodyColor: palette.text, displayColor: palette.text),
    appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent),
    colorScheme: base.colorScheme.copyWith(
        primary: palette.accent,
        onPrimary: palette.onAccent,
        surface: palette.background),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.onAccent,
            minimumSize: const Size.fromHeight(48),
            shape: shape,
            textStyle: base.textTheme.labelLarge
                ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            backgroundColor: palette.raised,
            foregroundColor: palette.text,
            minimumSize: const Size.fromHeight(48),
            shape: shape,
            side: BorderSide(color: palette.divider),
            textStyle: base.textTheme.labelLarge
                ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600))),
  );
}
