import 'dart:math' as math;

import 'cube_writer.dart';

typedef Rgb = List<double>;
typedef LookFn = Rgb Function(double r, double g, double b);

/// An original gremote look defined by parametric colour operations on
/// display-referred sRGB values.
class BuiltinLook {
  const BuiltinLook({
    required this.slug,
    required this.name,
    required this.description,
    required this.map,
  });

  final String slug;
  final String name;
  final String description;
  final LookFn map;

  String get id => 'builtin:$slug';
  String get assetPath => 'assets/luts/gremote-$slug.cube';

  String toCube({int size = 33}) =>
      writeCube(title: 'gremote $slug', size: size, map: map);
}

const builtinLooks = <BuiltinLook>[
  BuiltinLook(
    slug: 'warm-positive',
    name: '暖调正片',
    description: '提亮中间调，偏暖的高光与饱满色彩。',
    map: _warmPositive,
  ),
  BuiltinLook(
    slug: 'cool-negative',
    name: '冷调负片',
    description: '低反差、抬起的黑位与青色阴影。',
    map: _coolNegative,
  ),
  BuiltinLook(
    slug: 'hard-mono',
    name: '高反差黑白',
    description: '红滤镜式通道混合与强烈的 S 曲线。',
    map: _hardMono,
  ),
  BuiltinLook(
    slug: 'pale',
    name: '淡雅',
    description: '柔和对比、低饱和与轻微褪色。',
    map: _pale,
  ),
  BuiltinLook(
    slug: 'night-teal-gold',
    name: '夜街青金',
    description: '青色阴影与金色高光的城市夜色。',
    map: _nightTealGold,
  ),
];

double _luma(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

double _smooth(double x) => x * x * (3 - 2 * x);

double _sCurve(double x, double amount) => x + (_smooth(x) - x) * amount;

double _fade(double x, double black, double white) =>
    black + x * (white - black);

double _gamma(double x, double gamma) => math.pow(x, gamma).toDouble();

Rgb _saturate(Rgb rgb, double amount) {
  final l = _luma(rgb[0], rgb[1], rgb[2]);
  return [for (final c in rgb) l + (c - l) * amount];
}

Rgb _splitTone(Rgb rgb, Rgb shadow, Rgb highlight) {
  final l = _luma(rgb[0], rgb[1], rgb[2]).clamp(0.0, 1.0);
  final ws = (1 - l) * (1 - l);
  final wh = l * l;
  return [
    for (var i = 0; i < 3; i++) rgb[i] + shadow[i] * ws + highlight[i] * wh
  ];
}

Rgb _warmPositive(double r, double g, double b) {
  var rgb = [r, g, b].map((c) => _gamma(c, 0.94)).toList();
  rgb = rgb.map((c) => _sCurve(c, 0.35)).toList();
  rgb = _saturate(rgb, 1.14);
  rgb = [rgb[0] * 1.03, rgb[1] * 1.005, rgb[2] * 0.94];
  return _splitTone(rgb, const [0.0, 0.0, 0.01], const [0.03, 0.015, -0.02]);
}

Rgb _coolNegative(double r, double g, double b) {
  var rgb = [r, g, b].map((c) => _sCurve(c, -0.2)).toList();
  rgb = rgb.map((c) => _fade(c, 0.045, 0.97)).toList();
  rgb = _saturate(rgb, 0.88);
  return _splitTone(rgb, const [-0.02, 0.03, 0.05], const [0.015, 0.01, 0.0]);
}

Rgb _hardMono(double r, double g, double b) {
  final mixed = 0.35 * r + 0.5 * g + 0.15 * b;
  final toned = _fade(_sCurve(_sCurve(mixed, 0.7), 0.4), -0.02, 1.0);
  return [toned, toned, toned];
}

Rgb _pale(double r, double g, double b) {
  var rgb = [r, g, b].map((c) => _sCurve(c, -0.3)).toList();
  rgb = rgb.map((c) => _fade(c, 0.06, 0.95)).toList();
  rgb = _saturate(rgb, 0.72);
  return [rgb[0] * 1.01, rgb[1], rgb[2] * 0.99];
}

Rgb _nightTealGold(double r, double g, double b) {
  var rgb = [r, g, b].map((c) => _sCurve(c, 0.25)).toList();
  rgb = _saturate(rgb, 1.05);
  return _splitTone(rgb, const [-0.03, 0.05, 0.07], const [0.08, 0.045, -0.05]);
}
