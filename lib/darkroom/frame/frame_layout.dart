import 'package:meta/meta.dart';

import '../model/edit_document.dart';
import '../model/export_recipe.dart';
import '../model/photo_meta.dart';

@immutable
class PixelRect {
  const PixelRect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;

  PixelRect shift(int dx, int dy) => PixelRect(x + dx, y + dy, width, height);

  @override
  bool operator ==(Object other) =>
      other is PixelRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'PixelRect($x, $y, $width, $height)';
}

enum FrameFont { serif, sans, mono }

enum FrameAlign { left, right }

sealed class FrameElement {
  const FrameElement();
}

/// Text anchored at [x] (left or right edge per [align]) with its top at [y],
/// in overlay-local pixels.
class FrameText extends FrameElement {
  const FrameText({
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.color,
    required this.maxWidth,
    this.font = FrameFont.sans,
    this.align = FrameAlign.left,
    this.bold = false,
  });

  final String text;
  final double x;
  final double y;
  final double fontSize;
  final int color;
  final double maxWidth;
  final FrameFont font;
  final FrameAlign align;
  final bool bold;
}

class FrameRect extends FrameElement {
  const FrameRect(this.rect, this.color);

  final PixelRect rect;
  final int color;
}

/// A row of rounded film perforations filling [band] horizontally.
class FrameSprockets extends FrameElement {
  const FrameSprockets({required this.band, required this.color});

  final PixelRect band;
  final int color;
}

class OverlayRegion {
  const OverlayRegion(this.rect, this.elements);

  /// Canvas pixels.
  final PixelRect rect;
  final List<FrameElement> elements;
}

class FrameLayout {
  const FrameLayout({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.background,
    required this.photo,
    required this.overlays,
  });

  final int canvasWidth;
  final int canvasHeight;

  /// ARGB.
  final int background;
  final PixelRect photo;
  final List<OverlayRegion> overlays;
}

/// Already-formatted frame text; null entries are hidden or unknown.
@immutable
class FrameContent {
  const FrameContent({
    this.model,
    this.params,
    this.date,
    this.title,
    this.location,
  });

  factory FrameContent.from(
    PhotoMeta meta, {
    required String title,
    required String location,
    Set<FrameField> hidden = const {},
  }) {
    String? shown(FrameField field, String? value) =>
        hidden.contains(field) || value == null || value.trim().isEmpty
            ? null
            : value.trim();
    final params = [
      shown(FrameField.focal, meta.focalLabel),
      shown(FrameField.aperture, meta.apertureLabel),
      shown(FrameField.shutter, meta.shutterLabel),
      shown(FrameField.iso, meta.isoLabel),
    ].whereType<String>().join(' ');
    return FrameContent(
      model: shown(FrameField.model, meta.modelLabel),
      params: params.isEmpty ? null : params,
      date: shown(FrameField.date, meta.dateLabel),
      title: shown(FrameField.title, title),
      location: shown(FrameField.location, location),
    );
  }

  final String? model;
  final String? params;
  final String? date;
  final String? title;
  final String? location;

  String? get titleLine {
    final parts = [title, location].whereType<String>();
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Photo size after the export size preset; never upscales.
(int, int) scaledPhotoSize(int width, int height, ExportSize size) {
  final target = size.longEdge;
  final longEdge = width > height ? width : height;
  if (target == null || longEdge <= target) return (width, height);
  final scale = target / longEdge;
  return width >= height
      ? (target, (height * scale).round())
      : ((width * scale).round(), target);
}

abstract final class FramePalette {
  static const classicBackground = 0xFFFFFFFF;
  static const classicText = 0xFF151515;
  static const classicMuted = 0xFF707070;
  static const streetBackground = 0xFF0C100E;
  static const streetGold = 0xFFC7A86F;
  static const streetMuted = 0xFF9C9A90;
  static const contactBackground = 0xFF111111;
  static const contactEdge = 0xFFE0913C;
  static const contactHoles = 0xFFE6E0D2;
  static const contactMuted = 0xFFB8B2A4;
}

FrameLayout computeFrameLayout({
  required int photoWidth,
  required int photoHeight,
  required FrameStyle style,
  required FrameRatio ratio,
  required FrameContent content,
}) {
  final base = switch (style) {
    FrameStyle.classic => _classic(photoWidth, photoHeight, content),
    FrameStyle.street => _street(photoWidth, photoHeight, content),
    FrameStyle.contact => _contact(photoWidth, photoHeight, content),
  };
  final aspect = ratio.aspect;
  if (aspect == null) return base;
  final (rw, rh) = aspect;
  final units = [
    (base.canvasWidth + rw - 1) ~/ rw,
    (base.canvasHeight + rh - 1) ~/ rh,
  ].reduce((a, b) => a > b ? a : b);
  final width = units * rw;
  final height = units * rh;
  final dx = (width - base.canvasWidth) ~/ 2;
  final dy = (height - base.canvasHeight) ~/ 2;
  return FrameLayout(
    canvasWidth: width,
    canvasHeight: height,
    background: base.background,
    photo: base.photo.shift(dx, dy),
    overlays: [
      for (final o in base.overlays)
        OverlayRegion(o.rect.shift(dx, dy), o.elements),
    ],
  );
}

int _long(int w, int h) => w > h ? w : h;

FrameLayout _classic(int pw, int ph, FrameContent content) {
  final l = _long(pw, ph);
  final side = (0.035 * l).round();
  final bar = (0.11 * l).round();
  final b = bar.toDouble();
  final elements = <FrameElement>[
    if (content.model != null)
      FrameText(
          text: content.model!,
          x: 0,
          y: 0.24 * b,
          fontSize: 0.2 * b,
          color: FramePalette.classicText,
          maxWidth: pw * 0.55,
          font: FrameFont.serif,
          bold: true),
    if (content.titleLine != null)
      FrameText(
          text: content.titleLine!,
          x: 0,
          y: 0.56 * b,
          fontSize: 0.12 * b,
          color: FramePalette.classicMuted,
          maxWidth: pw * 0.55),
    if (content.params != null)
      FrameText(
          text: content.params!,
          x: pw.toDouble(),
          y: 0.27 * b,
          fontSize: 0.14 * b,
          color: FramePalette.classicText,
          maxWidth: pw * 0.43,
          font: FrameFont.mono,
          align: FrameAlign.right),
    if (content.date != null)
      FrameText(
          text: content.date!,
          x: pw.toDouble(),
          y: 0.56 * b,
          fontSize: 0.12 * b,
          color: FramePalette.classicMuted,
          maxWidth: pw * 0.43,
          font: FrameFont.mono,
          align: FrameAlign.right),
  ];
  return FrameLayout(
    canvasWidth: pw + 2 * side,
    canvasHeight: side + ph + bar,
    background: FramePalette.classicBackground,
    photo: PixelRect(side, side, pw, ph),
    overlays: [OverlayRegion(PixelRect(side, side + ph, pw, bar), elements)],
  );
}

FrameLayout _street(int pw, int ph, FrameContent content) {
  final l = _long(pw, ph);
  final margin = (0.045 * l).round();
  final bar = (0.12 * l).round();
  final line = (0.0012 * l).round() < 2 ? 2 : (0.0012 * l).round();
  final gap = (0.008 * l).round();
  final outer = PixelRect(margin - gap - line, margin - gap - line,
      pw + 2 * (gap + line), ph + 2 * (gap + line));
  OverlayRegion hairline(PixelRect rect) => OverlayRegion(rect, [
        FrameRect(
            PixelRect(0, 0, rect.width, rect.height), FramePalette.streetGold)
      ]);
  final infoTop = margin + ph + gap + line;
  final infoHeight = margin + ph + bar - infoTop;
  final h = infoHeight.toDouble();
  final elements = <FrameElement>[
    if (content.model != null)
      FrameText(
          text: content.model!,
          x: 0,
          y: 0.3 * h,
          fontSize: 0.2 * h,
          color: FramePalette.streetGold,
          maxWidth: pw * 0.55,
          font: FrameFont.serif),
    if (content.titleLine != null)
      FrameText(
          text: content.titleLine!,
          x: 0,
          y: 0.6 * h,
          fontSize: 0.12 * h,
          color: FramePalette.streetMuted,
          maxWidth: pw * 0.55),
    if (content.params != null)
      FrameText(
          text: content.params!,
          x: pw.toDouble(),
          y: 0.33 * h,
          fontSize: 0.13 * h,
          color: FramePalette.streetGold,
          maxWidth: pw * 0.43,
          font: FrameFont.mono,
          align: FrameAlign.right),
    if (content.date != null)
      FrameText(
          text: content.date!,
          x: pw.toDouble(),
          y: 0.6 * h,
          fontSize: 0.11 * h,
          color: FramePalette.streetMuted,
          maxWidth: pw * 0.43,
          font: FrameFont.mono,
          align: FrameAlign.right),
  ];
  return FrameLayout(
    canvasWidth: pw + 2 * margin,
    canvasHeight: margin + ph + bar,
    background: FramePalette.streetBackground,
    photo: PixelRect(margin, margin, pw, ph),
    overlays: [
      hairline(PixelRect(outer.x, outer.y, outer.width, line)),
      hairline(PixelRect(outer.x, outer.bottom - line, outer.width, line)),
      hairline(
          PixelRect(outer.x, outer.y + line, line, outer.height - 2 * line)),
      hairline(PixelRect(
          outer.right - line, outer.y + line, line, outer.height - 2 * line)),
      OverlayRegion(PixelRect(margin, infoTop, pw, infoHeight), elements),
    ],
  );
}

FrameLayout _contact(int pw, int ph, FrameContent content) {
  final l = _long(pw, ph);
  final side = (0.03 * l).round();
  final strip = (0.085 * l).round();
  final width = pw + 2 * side;
  final s = strip.toDouble();
  final holeBand = (0.34 * s).round();
  final edge = [
    'GRemote',
    content.model,
    content.params,
    content.date,
    '01',
  ].whereType<String>().join(' · ');
  final top = <FrameElement>[
    FrameSprockets(
        band: PixelRect(0, (0.16 * s).round(), width, holeBand),
        color: FramePalette.contactHoles),
    if (content.titleLine != null)
      FrameText(
          text: content.titleLine!,
          x: side.toDouble(),
          y: 0.6 * s,
          fontSize: 0.16 * s,
          color: FramePalette.contactMuted,
          maxWidth: pw.toDouble()),
  ];
  final bottom = <FrameElement>[
    FrameText(
        text: edge,
        x: side.toDouble(),
        y: 0.12 * s,
        fontSize: 0.16 * s,
        color: FramePalette.contactEdge,
        maxWidth: pw.toDouble(),
        font: FrameFont.mono),
    FrameSprockets(
        band: PixelRect(0, (0.5 * s).round(), width, holeBand),
        color: FramePalette.contactHoles),
  ];
  return FrameLayout(
    canvasWidth: width,
    canvasHeight: ph + 2 * strip,
    background: FramePalette.contactBackground,
    photo: PixelRect(side, strip, pw, ph),
    overlays: [
      OverlayRegion(PixelRect(0, 0, width, strip), top),
      OverlayRegion(PixelRect(0, strip + ph, width, strip), bottom),
    ],
  );
}
