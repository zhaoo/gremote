import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'official_film_library.dart';

/// Public numeric data only. Fetching, transport trust, caching and camera
/// compatibility belong to the caller; downloaded JavaScript is never used.
const officialFilmColorSourcePaths = <String>[
  '/gr3/film-catalog.json',
  '/gr3/5207-lut.json',
  '/gr3/harman-luts.json',
  '/gr3/curated-luts.json',
  '/gr3/newstocks-luts.json',
  '/gr3/style-filters-luts.json',
  '/gr3/spectral-luts.json',
  '/gr3/d76-luts.json',
  '/gr3/anime-e6-luts.json',
  '/gr3/c41-luts.json',
  '/gr3/extra-films-luts.json',
  '/gr3/four-looks-luts.json',
  '/gr3/leica-luts.json',
];

const leicaFilmIds = <int>{331, 332, 333, 334};

/// A portable, immutable RGB approximation for phone editing. This carries no
/// camera renderer identity and cannot authorize an SD record or camera write.
class OfficialColorLut {
  OfficialColorLut._(
      this.filmId, this.name, this.variant, this.size, Uint8List bytes)
      : cube = bytes.asUnmodifiableView(),
        contentHash = sha256.convert(bytes).toString();

  final int filmId, size;
  final String name, variant, contentHash;
  final Uint8List cube;
  String get id => 'official:$filmId:$variant:$contentHash';
  String get approximationLabel => '官网色彩预览近似，不含颗粒、光晕等空间效果';
}

void _need(bool ok) {
  if (!ok) throw const FormatException('官网色彩数据格式无效');
}

List<int> _integers(dynamic value, int count, int min, int max) {
  _need(value is List && value.length == count);
  return List<int>.unmodifiable((value as List).map((v) {
    _need(v is int && v >= min && v <= max);
    return v as int;
  }));
}

Map _map(dynamic value) {
  _need(value is Map);
  return value as Map;
}

void _geometry(Map source) => _need(source['size'] == 15 &&
    source['bits'] == 8 &&
    source['order'] == 'RGB, blue fastest');

Uint8List _cube(int size, List<double> Function(int r, int g, int b) sample) {
  final text = StringBuffer()
    ..writeln('# M10V official RGB color preview approximation v1')
    ..writeln('LUT_3D_SIZE $size')
    ..writeln('DOMAIN_MIN 0.0 0.0 0.0')
    ..writeln('DOMAIN_MAX 1.0 1.0 1.0');
  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        text.writeln(sample(r, g, b)
            .map((v) => (v.clamp(0.0, 1.0) + 0.0).toStringAsFixed(8))
            .join(' '));
      }
    }
  }
  return Uint8List.fromList(utf8.encode(text.toString()));
}

/// Compiles supported entries from decoded public JSON maps keyed by exact
/// [officialFilmColorSourcePaths]. Missing files/unknown future film IDs produce
/// no LUT, keeping those catalog entries browsable but unavailable for editing.
/// Supplied known formats are bounded and fail closed on malformed numeric data.
///
/// Regular stock tables use `values`; native-profile families use only
/// `native_values`. Harman defaults are Phoenix EI200 and RED EI125; other
/// variants are `ei120`, `ei64`, `ei250`. Output follows catalog order, then EI
/// parameter order. 33 (800T), 289 and 290 need distinct authored/effect render
/// contracts and are deliberately unavailable here.
List<OfficialColorLut> compileOfficialFilmLuts({
  required List<OfficialFilm> films,
  required Map<String, Map<String, dynamic>> sources,
}) {
  _need(films.length <= 256 &&
      sources.length <= officialFilmColorSourcePaths.length);
  final metadata = <int, OfficialFilm>{};
  for (final film in films) {
    _need(!metadata.containsKey(film.id));
    metadata[film.id] = film;
  }
  // Bound all supplied JSON, including unused fields and unknown source paths.
  var bytes = 0;
  try {
    for (final source in sources.values) {
      bytes += utf8.encode(jsonEncode(source)).length;
      _need(bytes <= 16 * 1024 * 1024);
    }
  } on JsonUnsupportedObjectError {
    throw const FormatException('官网色彩数据包含非有限数值');
  }
  final output = <OfficialColorLut>[];
  final seen = <String>{};
  void add(int id, String variant, int size, Uint8List cube) {
    _need(seen.add('$id/$variant'));
    final film = metadata[id];
    if (film != null) {
      output.add(OfficialColorLut._(id, film.name, variant, size, cube));
    }
  }

  final legacy = sources['/gr3/film-catalog.json'];
  if (legacy != null) {
    final looks = legacy['looks'];
    _need(looks is List && looks.length == 32);
    for (var i = 0; i < 32; i++) {
      final look = _map((looks as List)[i]);
      final matrix = _integers(look['matrixQ13'], 9, -32768, 32767);
      final post = _integers(look['postQ512'], 9, -32768, 32767);
      final curves = look['curves'];
      _need(curves is List && curves.length == 3);
      final channels = [
        for (final curve in curves as List) _integers(curve, 256, 0, 16383)
      ];
      if (!metadata.containsKey(34 + i)) continue;
      // Same matrix -> linear full-curve interpolation -> post transform as the
      // website preview. Sampling on a 33^3 lattice is explicitly approximate.
      add(
          34 + i,
          'default',
          33,
          _cube(33, (r, g, b) {
            final input = [r * 255 / 32, g * 255 / 32, b * 255 / 32];
            final tone = List<double>.generate(3, (c) {
              var at = 0.0;
              for (var j = 0; j < 3; j++) {
                at += input[j] * matrix[c * 3 + j] / 8192;
              }
              at = at.clamp(0.0, 255.0);
              final lo = at.floor(), hi = (lo + 1).clamp(0, 255);
              final values = channels[c];
              return (values[lo] + (values[hi] - values[lo]) * (at - lo)) /
                  16383;
            });
            return List<double>.generate(3, (c) {
              var value = 0.0;
              for (var j = 0; j < 3; j++) {
                value += tone[j] * post[c * 3 + j] / 512;
              }
              return value;
            });
          }));
    }
  }

  void table(int id, String variant, dynamic raw) {
    final values = _integers(raw, 15 * 15 * 15 * 3, 0, 255);
    // Source axes are RGB/blue-fastest; .cube is RGB/red-fastest.
    add(
        id,
        variant,
        15,
        _cube(15, (r, g, b) {
          final at = ((r * 15 + g) * 15 + b) * 3;
          return [for (var c = 0; c < 3; c++) values[at + c] / 255];
        }));
  }

  final day = sources['/gr3/5207-lut.json'];
  if (day != null) {
    _geometry(day);
    table(66, 'default', day['values']);
  }
  const families = <String, Iterable<int>>{
    'harman': [67, 68],
    'curated': [69, 70, 71, 72],
    'newstocks': [73, 74, 75, 76, 77, 78],
    'style-filters': [291, 292, 293, 294, 295, 296, 297],
    'spectral': [298],
    'd76': [299, 300, 301, 302, 303, 304, 305],
    'anime-e6': [309, 310, 311],
    'c41': [312, 313, 322, 323, 324, 325, 326],
    'extra-films': [314, 315, 316, 317],
    'four-looks': [318, 319, 320, 321],
    'leica': leicaFilmIds,
  };
  for (final family in families.entries) {
    final source = sources['/gr3/${family.key}-luts.json'];
    if (source == null) continue;
    _geometry(source);
    final stocks = source['stocks'];
    _need(stocks is List && stocks.length <= 256);
    for (final row in stocks as List) {
      final stock = _map(row), id = stock['id'];
      if (id is! int || !family.value.contains(id)) continue;
      var variant = 'default';
      if (family.key == 'harman') {
        final ei = stock['ei'];
        _need(
            ei is int && (id == 67 ? [200, 120] : [125, 64, 250]).contains(ei));
        if (ei != (id == 67 ? 200 : 125)) variant = 'ei$ei';
      }
      final native = const {
        'anime-e6',
        'c41',
        'extra-films',
        'four-looks',
        'leica',
      }.contains(family.key);
      table(id, variant, stock[native ? 'native_values' : 'values']);
    }
  }
  final order = {for (var i = 0; i < films.length; i++) films[i].id: i};
  const variants = ['default', 'ei120', 'ei64', 'ei250'];
  output.sort((a, b) {
    final byFilm = order[a.filmId]!.compareTo(order[b.filmId]!);
    return byFilm != 0
        ? byFilm
        : variants.indexOf(a.variant).compareTo(variants.indexOf(b.variant));
  });
  return List.unmodifiable(output);
}
