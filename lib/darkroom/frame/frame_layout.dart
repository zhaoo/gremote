import 'dart:math' as math;

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
      ? (target, math.max(1, (height * scale).round()))
      : (math.max(1, (width * scale).round()), target);
}

abstract final class FramePalette {
  static const classicBackground = 0xFFFFFFFF;
  static const classicText = 0xFF151515;
  static const classicMuted = 0xFF707070;
  static const streetBackground = 0xFF0C100E;
  static const streetGold = 0xFFBCA57F;
  static const streetMuted = 0xFF9C9A90;
  static const contactBackground = 0xFF111111;
  static const contactEdge = 0xFFC4A06D;
  static const contactHoles = 0xFF8B867A;
  static const contactMuted = 0xFFB8B2A4;
}

FrameLayout computeFrameLayout({
  required int photoWidth,
  required int photoHeight,
  required FrameStyle style,
  required FrameRatio ratio,
  required FrameContent content,
  double borderWidth = .035,
  bool dateStamp = false,
}) {
  final margin =
      borderWidth.isFinite ? borderWidth.clamp(0, .2).toDouble() : .035;
  final factor = margin / .035;
  final frame = switch (style) {
    FrameStyle.classic => _classic(photoWidth, photoHeight, content, factor),
    FrameStyle.street => _street(photoWidth, photoHeight, content, factor),
    FrameStyle.contact => _contact(photoWidth, photoHeight, content, factor),
    FrameStyle.white => _plain(photoWidth, photoHeight, margin, false),
    FrameStyle.black => _plain(photoWidth, photoHeight, margin, true),
    FrameStyle.polaroid =>
      _plain(photoWidth, photoHeight, margin, false, polaroid: true),
    FrameStyle.none => FrameLayout(
        canvasWidth: photoWidth,
        canvasHeight: photoHeight,
        background: FramePalette.classicBackground,
        photo: PixelRect(0, 0, photoWidth, photoHeight),
        overlays: const [],
      ),
  };
  final base = !dateStamp || content.date == null || content.date!.isEmpty
      ? frame
      : FrameLayout(
          canvasWidth: frame.canvasWidth,
          canvasHeight: frame.canvasHeight,
          background: frame.background,
          photo: frame.photo,
          overlays: [...frame.overlays, _dateStamp(frame.photo, content.date!)],
        );
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

// The caption is deliberately quieter than the photo. A personal title leads
// the first row; camera and exposure details sit on a separate baseline.
List<FrameElement> _caption(int width, int height, FrameContent content,
    {required int primary, required int muted}) {
  final w = width.toDouble(), h = height.toDouble();
  final headline = content.titleLine ?? content.model;
  final hasTitle = content.titleLine != null;
  return [
    if (headline != null)
      FrameText(
        text: headline,
        x: 0,
        y: h * 0.18,
        fontSize: h * 0.22,
        color: primary,
        maxWidth: content.date == null ? w : w * 0.70,
        bold: hasTitle,
      ),
    if (content.date != null)
      FrameText(
        text: content.date!,
        x: w,
        y: h * 0.22,
        fontSize: h * 0.135,
        color: muted,
        maxWidth: headline == null ? w : w * 0.27,
        align: FrameAlign.right,
      ),
    if (hasTitle && content.model != null)
      FrameText(
        text: content.model!,
        x: 0,
        y: h * 0.57,
        fontSize: h * 0.15,
        color: muted,
        maxWidth: content.params == null ? w : w * 0.35,
      ),
    if (content.params != null)
      FrameText(
        text: content.params!,
        x: hasTitle && content.model != null ? w : 0,
        y: h * 0.57,
        fontSize: h * 0.15,
        color: muted,
        maxWidth: hasTitle && content.model != null ? w * 0.62 : w,
        font: FrameFont.mono,
        align: hasTitle && content.model != null
            ? FrameAlign.right
            : FrameAlign.left,
      ),
  ];
}

bool _hasCaption(FrameContent content) => [
      content.titleLine,
      content.model,
      content.params,
      content.date
    ].any((value) => value != null && value.isNotEmpty);

int _pixels(double value) => value.round().clamp(1, 1 << 30);
int _short(int w, int h) => w < h ? w : h;

FrameLayout _classic(int pw, int ph, FrameContent content, double factor) {
  final unit = _short(pw, ph);
  final side = _margin(0.035 * unit * factor);
  final bar = _hasCaption(content) ? _margin(0.115 * unit * factor) : side;
  return FrameLayout(
    canvasWidth: pw + 2 * side,
    canvasHeight: side + ph + bar,
    background: FramePalette.classicBackground,
    photo: PixelRect(side, side, pw, ph),
    overlays: [
      if (_hasCaption(content) && bar > 0)
        OverlayRegion(
            PixelRect(side, side + ph, pw, bar),
            _caption(pw, bar, content,
                primary: FramePalette.classicText,
                muted: FramePalette.classicMuted)),
    ],
  );
}

FrameLayout _street(int pw, int ph, FrameContent content, double factor) {
  final unit = _short(pw, ph);
  final margin = _margin(0.035 * unit * factor);
  final bar = _hasCaption(content) ? _margin(0.115 * unit * factor) : margin;
  // One short accent replaces the four bright rules surrounding the photo.
  final line = _pixels(unit * 0.001);
  final accent = _pixels(pw * 0.045);
  final info = _caption(pw, bar, content,
      primary: FramePalette.streetGold, muted: FramePalette.streetMuted);
  return FrameLayout(
    canvasWidth: pw + 2 * margin,
    canvasHeight: margin + ph + bar,
    background: FramePalette.streetBackground,
    photo: PixelRect(margin, margin, pw, ph),
    overlays: [
      if (_hasCaption(content) && bar > 0)
        OverlayRegion(PixelRect(margin, margin + ph, pw, bar), [
          FrameRect(PixelRect(0, _pixels(bar * 0.07), accent, line),
              FramePalette.streetGold),
          ...info,
        ]),
    ],
  );
}

FrameLayout _contact(int pw, int ph, FrameContent content, double factor) {
  final unit = _short(pw, ph);
  final side = _margin(0.035 * unit * factor);
  final strip = _margin(0.10 * unit * factor);
  final width = pw + 2 * side;
  final s = strip.toDouble();
  final holeBand = _pixels(0.18 * s);
  final edge = [content.model, content.params, content.date]
      .whereType<String>()
      .join('  ·  ');
  final top = <FrameElement>[
    FrameSprockets(
        band: PixelRect(side, _pixels(0.13 * s), pw, holeBand),
        color: FramePalette.contactHoles),
    if (content.titleLine != null)
      FrameText(
          text: content.titleLine!,
          x: side.toDouble(),
          y: 0.50 * s,
          fontSize: 0.22 * s,
          color: FramePalette.contactMuted,
          maxWidth: pw.toDouble()),
  ];
  final bottom = <FrameElement>[
    if (edge.isNotEmpty)
      FrameText(
          text: edge,
          x: side.toDouble(),
          y: 0.18 * s,
          fontSize: 0.15 * s,
          color: FramePalette.contactEdge,
          maxWidth: pw.toDouble(),
          font: FrameFont.mono),
    FrameSprockets(
        band: PixelRect(side, _pixels(0.63 * s), pw, holeBand),
        color: FramePalette.contactHoles),
  ];
  return FrameLayout(
    canvasWidth: width,
    canvasHeight: ph + 2 * strip,
    background: FramePalette.contactBackground,
    photo: PixelRect(side, strip, pw, ph),
    overlays: [
      if (strip > 0) OverlayRegion(PixelRect(0, 0, width, strip), top),
      if (strip > 0)
        OverlayRegion(PixelRect(0, strip + ph, width, strip), bottom),
    ],
  );
}

int _margin(double pixels) => pixels <= 0 ? 0 : _pixels(pixels);

FrameLayout _plain(int pw, int ph, double border, bool black,
    {bool polaroid = false}) {
  final side = _margin(_short(pw, ph) * border);
  final bottom = polaroid ? side * 4 : side;
  return FrameLayout(
    canvasWidth: pw + side * 2,
    canvasHeight: ph + side + bottom,
    background: black ? 0xff000000 : 0xffffffff,
    photo: PixelRect(side, side, pw, ph),
    overlays: const [],
  );
}

OverlayRegion _dateStamp(PixelRect photo, String date) {
  final short = _short(photo.width, photo.height);
  final inset = (short * .025).round();
  final width =
      math.max(1, math.min(photo.width - inset * 2, (short * .5).round()));
  final height =
      math.max(1, math.min(photo.height - inset * 2, (short * .065).round()));
  return OverlayRegion(
    PixelRect(photo.right - inset - width, photo.bottom - inset - height, width,
        height),
    [
      FrameText(
        text: date,
        x: width.toDouble(),
        y: 0,
        fontSize: math.min(short * .025, height * .8),
        color: 0xffffaa66,
        maxWidth: width.toDouble(),
        font: FrameFont.mono,
        align: FrameAlign.right,
      )
    ],
  );
}
