import 'package:flutter/material.dart';

/// UI colors only. Photograph pixels, export frames and protocol values never
/// resolve through this palette.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette(
      {required this.background,
      required this.surface,
      required this.raised,
      required this.text,
      required this.muted,
      required this.divider,
      required this.accent,
      required this.onAccent,
      required this.danger});

  static const dark = AppPalette(
      background: Color(0xFF171A1D),
      surface: Color(0xFF171A1D),
      raised: Color(0xFF23272A),
      text: Color(0xFFEFEEE8),
      muted: Color(0xFF9CA3A6),
      divider: Color(0xFF343A3E),
      accent: Color(0xFFE1E5E3),
      onAccent: Color(0xFF171A1D),
      danger: Color(0xFFD76A56));
  static const light = AppPalette(
      background: Color(0xFFF7F6F2),
      surface: Color(0xFFF7F6F2),
      raised: Color(0xFFF2F1EC),
      text: Color(0xFF222725),
      muted: Color(0xFF6B726F),
      divider: Color(0xFFD9DCD5),
      accent: Color(0xFF222725),
      onAccent: Color(0xFFF7F6F2),
      danger: Color(0xFFB33E2B));

  final Color background,
      surface,
      raised,
      text,
      muted,
      divider,
      accent,
      onAccent,
      danger;

  @override
  AppPalette copyWith(
          {Color? background,
          Color? surface,
          Color? raised,
          Color? text,
          Color? muted,
          Color? divider,
          Color? accent,
          Color? onAccent,
          Color? danger}) =>
      AppPalette(
          background: background ?? this.background,
          surface: surface ?? this.surface,
          raised: raised ?? this.raised,
          text: text ?? this.text,
          muted: muted ?? this.muted,
          divider: divider ?? this.divider,
          accent: accent ?? this.accent,
          onAccent: onAccent ?? this.onAccent,
          danger: danger ?? this.danger);

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
        background: Color.lerp(background, other.background, t)!,
        surface: Color.lerp(surface, other.surface, t)!,
        raised: Color.lerp(raised, other.raised, t)!,
        text: Color.lerp(text, other.text, t)!,
        muted: Color.lerp(muted, other.muted, t)!,
        divider: Color.lerp(divider, other.divider, t)!,
        accent: Color.lerp(accent, other.accent, t)!,
        onAccent: Color.lerp(onAccent, other.onAccent, t)!,
        danger: Color.lerp(danger, other.danger, t)!);
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light);
}
