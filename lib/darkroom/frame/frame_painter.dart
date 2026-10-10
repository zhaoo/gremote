import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'frame_layout.dart';

/// Draws overlay content in overlay-local coordinates multiplied by [scale],
/// so previews and full-resolution exports share one implementation.
abstract final class FramePainter {
  static void paintOverlay(Canvas canvas, OverlayRegion overlay,
      {double scale = 1}) {
    for (final element in overlay.elements) {
      switch (element) {
        case FrameText():
          _paintText(canvas, element, scale);
        case FrameRect(:final rect, :final color):
          canvas.drawRect(
            Rect.fromLTWH(rect.x * scale, rect.y * scale, rect.width * scale,
                rect.height * scale),
            Paint()..color = Color(color),
          );
        case FrameSprockets():
          _paintSprockets(canvas, element, scale);
      }
    }
  }

  static TextStyle _style(FrameText text, double scale) {
    final base = switch (text.font) {
      FrameFont.serif => const TextStyle(
          fontFamily: 'GRemoteEditorial',
          fontFamilyFallback: ['Noto Serif CJK SC', 'serif'],
          letterSpacing: 0.6,
        ),
      FrameFont.sans => const TextStyle(
          fontFamilyFallback: ['MiSans', 'Noto Sans CJK SC', 'PingFang SC'],
        ),
      FrameFont.mono => const TextStyle(
          fontFamily: 'monospace',
          fontFeatures: [ui.FontFeature.tabularFigures()],
          letterSpacing: 0.4,
        ),
    };
    return base.copyWith(
      fontSize: text.fontSize * scale,
      color: Color(text.color),
      fontWeight: text.bold ? FontWeight.w700 : FontWeight.w400,
      height: 1.1,
    );
  }

  static void _paintText(Canvas canvas, FrameText text, double scale) {
    final painter = TextPainter(
      text: TextSpan(text: text.text, style: _style(text, scale)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: text.maxWidth * scale);
    final dx = text.align == FrameAlign.left
        ? text.x * scale
        : text.x * scale - painter.width;
    painter.paint(canvas, Offset(dx, text.y * scale));
    painter.dispose();
  }

  static void _paintSprockets(
      Canvas canvas, FrameSprockets sprockets, double scale) {
    final band = sprockets.band;
    final holeHeight = band.height * scale;
    final holeWidth = holeHeight * 0.7;
    final gap = holeHeight * 0.8;
    final width = band.width * scale;
    final count = ((width + gap) / (holeWidth + gap)).floor();
    if (count <= 0) return;
    final used = count * holeWidth + (count - 1) * gap;
    var x = band.x * scale + (width - used) / 2;
    final paint = Paint()..color = Color(sprockets.color);
    final radius = Radius.circular(holeHeight * 0.18);
    for (var i = 0; i < count; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, band.y * scale, holeWidth, holeHeight), radius),
        paint,
      );
      x += holeWidth + gap;
    }
  }
}
