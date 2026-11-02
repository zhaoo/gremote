import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

enum PhotoAdjustment {
  exposure('曝光', 1, -3, 3),
  contrast('对比度', 2, -1, 1),
  highlights('高光', 3, -1, 1),
  shadows('阴影', 4, -1, 1),
  whites('白色', 5, -1, 1),
  blacks('黑色', 6, -1, 1),
  temperature('色温', 7, -1, 1),
  tint('色调', 8, -1, 1),
  saturation('饱和度', 9, -1, 1),
  vibrance('自然饱和度', 10, -1, 1),
  vignette('强度', 11, -1, 1),
  vignetteSize('范围', 12, 0, 1, .55),
  vignetteFeather('羽化', 13, 0, 1, .72),
  grain('强度', 14, 0, 1),
  grainSize('大小', 15, 0, 1, .28),
  grainRoughness('粗糙度', 16, 0, 1, .4),
  halation('强度', 17, 0, 1),
  halationRadius('范围', 18, 0, 1, .45),
  halationThreshold('高光阈值', 19, 0, 1, .65),
  bloom('强度', 20, 0, 1),
  bloomRadius('扩散', 21, 0, 1, .35),
  bloomThreshold('高光阈值', 22, 0, 1, .6),
  leak('强度', 23, 0, 1),
  leakPosition('位置', 24, 0, 1, .15),
  leakSpread('范围', 25, 0, 1, .55),
  leakHue('颜色', 26, 0, 1, .06),
  fade('强度', 27, 0, 1),
  monochrome('强度', 28, 0, 1);

  const PhotoAdjustment(this.label, this.indexInNative, this.min, this.max,
      [this.initial = 0]);
  final String label;
  final int indexInNative;
  final double min, max, initial;

  double normalized(Object? v) =>
      v is num && v.isFinite ? v.toDouble().clamp(min, max) : initial;

  String display(double value) => this == exposure
      ? '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}'
      : '${value > 0 && min < 0 ? '+' : ''}${(value * 100).round()}';
}

double _number(Object? v, double fallback, double lo, double hi) =>
    v is num && v.isFinite ? v.toDouble().clamp(lo, hi) : fallback;

@immutable
class CropEdit {
  const CropEdit(
      {this.left = 0,
      this.top = 0,
      this.width = 1,
      this.height = 1,
      this.quarterTurns = 0,
      this.flipX = false,
      this.flipY = false,
      this.angle = 0,
      this.aspectRatio = 0});

  factory CropEdit.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    final l = _number(m['left'], 0, 0, .999999);
    final t = _number(m['top'], 0, 0, .999999);
    return CropEdit(
        left: l,
        top: t,
        width: _number(m['width'], 1, .000001, 1 - l),
        height: _number(m['height'], 1, .000001, 1 - t),
        quarterTurns:
            (_number(m['quarterTurns'], 0, -10000, 10000).round() % 4),
        flipX: m['flipX'] == true,
        flipY: m['flipY'] == true,
        angle: _number(m['angle'], 0, -45, 45),
        aspectRatio: _number(m['aspectRatio'], 0, 0, 100));
  }

  final double left, top, width, height, angle, aspectRatio;
  final int quarterTurns;
  final bool flipX, flipY;
  Map<String, Object?> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
        'quarterTurns': quarterTurns,
        'flipX': flipX,
        'flipY': flipY,
        'angle': angle,
        'aspectRatio': aspectRatio
      };
  CropEdit copyWith(
          {double? left,
          double? top,
          double? width,
          double? height,
          int? quarterTurns,
          bool? flipX,
          bool? flipY,
          double? angle,
          double? aspectRatio}) =>
      CropEdit.fromJson({
        ...toJson(),
        if (left != null) 'left': left,
        if (top != null) 'top': top,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (quarterTurns != null) 'quarterTurns': quarterTurns,
        if (flipX != null) 'flipX': flipX,
        if (flipY != null) 'flipY': flipY,
        if (angle != null) 'angle': angle,
        if (aspectRatio != null) 'aspectRatio': aspectRatio
      });

  (int, int) outputSize(int sourceWidth, int sourceHeight) {
    final swap = quarterTurns.isOdd;
    final w = swap ? sourceHeight : sourceWidth;
    final h = swap ? sourceWidth : sourceHeight;
    return (
      math.max(1, _floatProduct(w, width).round()).clamp(1, w),
      math.max(1, _floatProduct(h, height).round()).clamp(1, h)
    );
  }

  static double _floatProduct(int pixels, double fraction) {
    final p = Float32List.fromList([pixels.toDouble(), fraction]);
    p[0] = p[0] * p[1];
    return p[0];
  }

  @override
  bool operator ==(Object other) =>
      other is CropEdit &&
      const MapEquality<String, Object?>().equals(toJson(), other.toJson());
  @override
  int get hashCode => Object.hash(
      left, top, width, height, quarterTurns, flipX, flipY, angle, aspectRatio);
}

@immutable
class CurvePoint {
  const CurvePoint(this.x, this.y);
  final double x, y;
  @override
  bool operator ==(Object other) =>
      other is CurvePoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

@immutable
class ToneCurve {
  const ToneCurve() : points = const [CurvePoint(0, 0), CurvePoint(1, 1)];
  const ToneCurve._(this.points);
  factory ToneCurve.fromPoints(Iterable<CurvePoint> points) {
    final byX = <double, double>{};
    for (final p in points.take(32)) {
      if (p.x.isFinite && p.y.isFinite) byX[p.x.clamp(0, 1)] = p.y.clamp(0, 1);
    }
    final xs = byX.keys.toList()..sort();
    if (xs.isEmpty) return const ToneCurve();
    byX.putIfAbsent(0, () => 0);
    byX.putIfAbsent(1, () => 1);
    final keys = byX.keys.toList()..sort();
    return ToneCurve._(
        List.unmodifiable(keys.map((x) => CurvePoint(x, byX[x]!))));
  }
  factory ToneCurve.fromJson(Object? j) => j is List
      ? ToneCurve.fromPoints(j
          .whereType<List>()
          .where((p) => p.length == 2)
          .map((p) => CurvePoint(_number(p[0], double.nan, 0, 1),
              _number(p[1], double.nan, 0, 1))))
      : const ToneCurve();
  final List<CurvePoint> points;
  List<List<double>> toJson() => [
        for (final p in points) [p.x, p.y]
      ];

  /// Monotone cubic Hermite interpolation: no ringing past adjacent tones.
  List<double> samples() {
    final n = points.length;
    final d = List<double>.generate(
        n - 1,
        (i) =>
            (points[i + 1].y - points[i].y) / (points[i + 1].x - points[i].x));
    final m = List<double>.filled(n, 0);
    m[0] = d.first;
    m[n - 1] = d.last;
    for (var i = 1; i < n - 1; i++) {
      if (d[i - 1] * d[i] > 0) m[i] = 2 * d[i - 1] * d[i] / (d[i - 1] + d[i]);
    }
    for (var i = 0; i < d.length; i++) {
      if (d[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
        continue;
      }
      final a = m[i] / d[i], b = m[i + 1] / d[i], sum = a * a + b * b;
      if (sum > 9) {
        final scale = 3 / math.sqrt(sum);
        m[i] = scale * a * d[i];
        m[i + 1] = scale * b * d[i];
      }
    }
    var segment = 0;
    return List.generate(256, (i) {
      final x = i / 255;
      while (segment < n - 2 && x > points[segment + 1].x) {
        segment++;
      }
      final a = points[segment],
          b = points[segment + 1],
          h = b.x - a.x,
          t = (x - a.x) / h;
      final t2 = t * t, t3 = t2 * t;
      return ((2 * t3 - 3 * t2 + 1) * a.y +
              (t3 - 2 * t2 + t) * h * m[segment] +
              (-2 * t3 + 3 * t2) * b.y +
              (t3 - t2) * h * m[segment + 1])
          .clamp(0, 1)
          .toDouble();
    });
  }

  @override
  bool operator ==(Object other) =>
      other is ToneCurve &&
      const ListEquality<CurvePoint>().equals(points, other.points);
  @override
  int get hashCode => Object.hashAll(points);
}

@immutable
class PhotoEdits {
  const PhotoEdits()
      : _values = const {},
        crop = const CropEdit(),
        seed = 7331,
        curves = const [ToneCurve(), ToneCurve(), ToneCurve(), ToneCurve()];
  const PhotoEdits._(this._values, this.crop, this.seed, this.curves);
  factory PhotoEdits.fromJson(Object? json) {
    final j = json is Map ? json : const {};
    final v = j['values'] is Map ? j['values'] as Map : const {};
    final c = j['curves'] is List ? j['curves'] as List : const [];
    return PhotoEdits._(
        Map.unmodifiable({
          for (final a in PhotoAdjustment.values)
            if (v.containsKey(a.name)) a: a.normalized(v[a.name])
        }),
        CropEdit.fromJson(j['crop']),
        _number(j['seed'], 7331, 1, 16777215).round(),
        List.unmodifiable(List.generate(
            4,
            (i) =>
                i < c.length ? ToneCurve.fromJson(c[i]) : const ToneCurve())));
  }
  final Map<PhotoAdjustment, double> _values;
  final CropEdit crop;
  final int seed;
  final List<ToneCurve> curves;
  double value(PhotoAdjustment a) => _values[a] ?? a.initial;
  PhotoEdits withValue(PhotoAdjustment a, double v) => PhotoEdits._(
      Map.unmodifiable({..._values, a: a.normalized(v)}), crop, seed, curves);
  PhotoEdits copyWith({CropEdit? crop, int? seed, List<ToneCurve>? curves}) =>
      PhotoEdits._(
          _values,
          crop == null ? this.crop : CropEdit.fromJson(crop.toJson()),
          (seed ?? this.seed).clamp(1, 16777215),
          curves == null
              ? this.curves
              : List.unmodifiable(List.generate(4,
                  (i) => i < curves.length ? curves[i] : const ToneCurve())));
  PhotoEdits withCurve(int channel, ToneCurve curve) => copyWith(
      curves: [for (var i = 0; i < 4; i++) i == channel ? curve : curves[i]]);
  Map<String, Object?> toJson() => {
        'values': {for (final a in PhotoAdjustment.values) a.name: value(a)},
        'crop': crop.toJson(),
        'seed': seed,
        'curves': [for (final c in curves) c.toJson()]
      };
  Float32List get nativeParameters {
    final p = Float32List(1062);
    p[0] = 1;
    for (final a in PhotoAdjustment.values) {
      p[a.indexInNative] = value(a);
    }
    p[29] = seed.toDouble();
    p.setRange(30, 38, [
      crop.left,
      crop.top,
      crop.width,
      crop.height,
      crop.quarterTurns.toDouble(),
      crop.flipX ? 1.0 : 0.0,
      crop.flipY ? 1.0 : 0.0,
      crop.angle
    ]);
    for (var c = 0; c < 4; c++) {
      p.setRange(38 + c * 256, 38 + (c + 1) * 256, curves[c].samples());
    }
    return p;
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoEdits &&
      crop == other.crop &&
      seed == other.seed &&
      const ListEquality<ToneCurve>().equals(curves, other.curves) &&
      PhotoAdjustment.values.every((a) => value(a) == other.value(a));
  @override
  int get hashCode => Object.hash(crop, seed, Object.hashAll(curves),
      Object.hashAll(PhotoAdjustment.values.map(value)));
}
