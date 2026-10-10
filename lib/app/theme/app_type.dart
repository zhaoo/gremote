import 'package:flutter/material.dart';

abstract final class GRemoteType {
  static const display = TextStyle(
    fontFamily: 'GRemoteEditorial',
    fontFamilyFallback: ['Noto Serif CJK SC'],
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    height: 1.12,
  );

  static const body = TextStyle(
    fontFamilyFallback: ['PingFang SC', 'Noto Sans CJK SC'],
    height: 1.35,
  );

  static const numeric = TextStyle(
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.5,
  );
}
