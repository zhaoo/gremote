import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import '../../film/model/film_recipe.dart' show canonicalJson;

import '../companion/companion_protocol.dart';
import '../companion/camera_film_catalog.dart';
import '../capture/capture_tracker.dart';
import '../http/camera_files.dart';
import '../params/param_writer.dart';
import '../sync/camera_state.dart';

const recipeKeys = [
  'WBMode',
  'WBColorTemp',
  'WBShift',
  'meteringMode',
  'aspectRatio',
  'stillFormat',
  'av',
  'tv',
  'sv',
  'xv',
];
const exposureRecipeKeys = {'av', 'tv', 'sv', 'xv'};
const recipeEffectKeys = [
  'filmTexture',
  'wbGreenMagenta',
  'wbBlueAmber',
  'wbKelvin',
  'aspect',
  'hdf',
  'vignetteStrength',
  'vignetteEnabled',
  'imprint',
  'border',
  'stamp',
  'stampFormat',
  'stampCorner',
  'stampColor',
  'filmNameStamp',
];

int exposureRecipeCrc(Uint8List bytes, int length) {
  var crc = 0xffffffff;
  for (var i = 0; i < length; i++) {
    crc ^= bytes[i];
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320);
    }
  }
  return crc ^ 0xffffffff;
}

/// Metadata from an original GR III still, before any app-side interpretation.
class RecordedExposure {
  RecordedExposure._(this._bytes);

  final Uint8List _bytes;
  ByteData get _words => ByteData.sublistView(_bytes);
  int get filmId => _words.getUint16(16, Endian.little);
  int get kelvin => _words.getUint16(68, Endian.little);
  (int, int) get whiteBalanceShift => (14 - _bytes[74], 14 - _bytes[75]);
  String get catalog => _hex(108, 140);
  String get renderer => _hex(140, 172);
  String? get customHash =>
      filmId >= 79 && filmId <= 288 ? _hex(76, 108) : null;

  bool matchesFilm(Map<String, Object?> film) =>
      film['filmId'] == filmId && film['customHash'] == customHash;

  ShootingRecipe resolve(CameraState camera, CompanionSnapshot snapshot,
      Map<String, dynamic> contract) {
    if (catalog != snapshot.wire['catalogHash'] ||
        renderer != snapshot.wire['rendererHash']) {
      throw const FormatException('照片与机身的胶卷版本不匹配');
    }
    if (!snapshot.slots.any(matchesFilm)) {
      throw const FormatException('请先安装拍摄时使用的胶卷版本');
    }
    const whiteBalance = [
      'auto',
      'multiAuto',
      'daylight',
      'shade',
      'cloud',
      'daylightFluorescent',
      'dayWhiteFluorescent',
      'coolWhiteFluorescent',
      'warmWhiteFluorescent',
      'tungsten',
      'incandescent',
      'manual1',
      'manual2',
      'manual3',
      'colorTemp1',
      'colorTemp2',
      'colorTemp3',
      'cte',
    ];
    const metering = ['multi', 'center', 'spot'];
    const formats = ['jpeg', 'rawdng', 'rawdng+jpeg'];
    final mode = _bytes[66];
    final meter = _bytes[65];
    final format = _bytes[67];
    final usesKelvin = mode >= 14 && mode <= 16;
    if (mode >= whiteBalance.length ||
        meter >= metering.length ||
        format >= formats.length ||
        _bytes[70] > 6 ||
        _bytes[72] > 2 ||
        _bytes[73] > 3 ||
        (usesKelvin && (kelvin < 2500 || kelvin > 10000))) {
      throw const FormatException('照片内的原厂拍摄设置超出支持范围');
    }
    final settings = {
      'WBMode': whiteBalance[mode],
      'meteringMode': metering[meter],
      if (camera.params.containsKey('stillFormat'))
        'stillFormat': formats[format],
    };
    for (final (index, key) in ['av', 'tv', 'sv', 'xv'].indexed) {
      final param = camera.params[key];
      if (param == null || !param.writable) continue;
      final raw = _words.getFloat32(48 + index * 4, Endian.little);
      final candidates = <(String, double)>[];
      for (final option in param.options) {
        final parts = option.split('/');
        final a = double.tryParse(parts.first);
        final b = parts.length == 2 ? double.tryParse(parts[1]) : 1.0;
        if (a == null || b == null || parts.length > 2 || b <= 0) continue;
        final n = a / b;
        if (key != 'xv' && n <= 0) continue;
        final apex = switch (key) {
          'av' => 2 * math.log(n) / math.ln2,
          'tv' => -math.log(n) / math.ln2,
          'sv' => 5 + math.log(n / 100) / math.ln2,
          _ => n,
        };
        final distance = (raw - apex).abs();
        if (distance <= 0.16) candidates.add((option, distance));
      }
      candidates.sort((a, b) => a.$2.compareTo(b.$2));
      if (candidates.isEmpty) {
        throw const FormatException('当前拍摄模式无法恢复照片中的曝光参数');
      }
      settings[key] = candidates.first.$1;
    }
    final stamp = _words.getUint32(36, Endian.little);
    final fx = _words.getUint32(40, Endian.little);
    final values = {
      'grain': _bytes[18],
      'haloGain': _bytes[20],
      'haloSpread': _bytes[21],
      'haloThreshold': _bytes[22],
      'haloProfile': _bytes[23],
      'grainSize': _bytes[24],
      'leakGain': _bytes[25],
      'leakPosition': _bytes[26],
      'leakSpread': _bytes[27],
      'leakVariation': (_bytes[28] & 0x80) == 0 ? _bytes[28] : 0,
      'filmExposure': _bytes[29],
      'charmeraColor': _bytes[31],
    };
    return ShootingRecipe(
      name: '原拍配方',
      catalog: catalog,
      renderer: renderer,
      film: {
        'filmId': filmId,
        'customHash': customHash,
        'parameters': {
          for (final entry in values.entries)
            if (cameraParameterSupported(entry.key, filmId, contract: contract))
              entry.key: entry.value,
        },
      },
      settings: settings,
      effects: {
        if ((_bytes[28] & 0xf0) == 0x80)
          'filmTexture': _bytes[24] |
              (_bytes[25] << 2) |
              (_bytes[26] << 4) |
              (_bytes[27] << 7) |
              ((_bytes[28] & 15) << 9),
        'wbGreenMagenta': _bytes[74],
        'wbBlueAmber': _bytes[75],
        if (usesKelvin) 'wbKelvin': kelvin,
        'aspect': _bytes[70],
        'hdf': _bytes[73],
        'border': _bytes[72],
        'vignetteEnabled': (fx >> 10) & 1,
        'vignetteStrength': 1 + ((fx >> 11) & 3),
        'imprint': (fx >> 7) & 7,
        'stamp': stamp & 255,
        'stampFormat': (stamp >> 8) & 255,
        'stampCorner': (stamp >> 16) & 255,
        'stampColor': (stamp >> 24) & 255,
        'filmNameStamp': _bytes[32] & 1,
      },
    );
  }

  String _hex(int start, int end) => _bytes
      .sublist(start, end)
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();

  static RecordedExposure? parse(String? hex, int? filmCode) {
    if (hex == null || !RegExp(r'^4d435232[0-9a-f]{344}$').hasMatch(hex)) {
      return null;
    }
    final bytes = Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    final recipe = RecordedExposure._(bytes);
    if (recipe._words.getUint32(172, Endian.little) !=
            exposureRecipeCrc(bytes, 172) ||
        recipe._words.getUint32(12, Endian.little) - 25 >= 10 ||
        recipe._words.getUint32(12, Endian.little) < 25 ||
        bytes[74] > 28 ||
        bytes[75] > 28 ||
        recipe.catalog == '0' * 64 ||
        recipe.renderer == '0' * 64) {
      return null;
    }
    if (recipe.customHash case final String hash) {
      final bank = bytes[30];
      if (bank < 21 ||
          bank > 254 ||
          hash == '0' * 64 ||
          filmCode != 0x2000 + (recipe.filmId - 79) * 235 + bank - 21) {
        return null;
      }
    } else if (recordedBuiltinFilmId(filmCode) != recipe.filmId ||
        recipe._hex(76, 108) != '0' * 64) {
      return null;
    }
    return recipe;
  }
}

class ShootingRecipe {
  ShootingRecipe({
    required this.name,
    required this.catalog,
    required this.renderer,
    required Map<String, Object?> film,
    required Map<String, String> settings,
    Map<String, int> effects = const {},
  })  : film = wireMap(film),
        settings = Map.unmodifiable(settings),
        effects = Map.unmodifiable(effects) {
    if (name.trim().isEmpty ||
        name.runes.length > 24 ||
        film['filmId'] is! int ||
        (film['filmId'] as int) <= 0 ||
        film['parameters'] is! Map ||
        !settings.keys.every(recipeKeys.contains) ||
        !effects.keys.every(recipeEffectKeys.contains)) {
      throw const FormatException('拍摄配方无效');
    }
  }

  factory ShootingRecipe.fromJson(Map<String, Object?> value) => ShootingRecipe(
        name: value['name'] as String,
        catalog: value['catalog'] as String,
        renderer: value['renderer'] as String,
        film: wireMap(value['film']),
        settings: Map<String, String>.from(value['settings'] as Map),
        effects: Map<String, int>.from((value['effects'] as Map?) ?? const {}),
      );

  final String name, catalog, renderer;
  final Map<String, Object?> film;
  final Map<String, String> settings;
  final Map<String, int> effects;

  Map<String, Object?> toJson() => {
        'name': name,
        'catalog': catalog,
        'renderer': renderer,
        'film': film,
        'settings': settings,
        'effects': effects,
      };

  static ShootingRecipe? fromCamera(String name, CompanionSnapshot snapshot,
      CameraState camera, Map<String, int> effects) {
    final active = snapshot.activeSlot;
    if (!camera.online ||
        camera.pending.isNotEmpty ||
        active == null ||
        snapshot.slots[active]['filmId'] == 0) return null;
    return ShootingRecipe(
      name: name,
      catalog: snapshot.wire['catalogHash'] as String,
      renderer: snapshot.wire['rendererHash'] as String,
      film: snapshot.slots[active],
      effects: effects,
      settings: {
        for (final key in recipeKeys)
          if (camera.params[key] case final parameter? when parameter.writable)
            if (parameter.current case final String value)
              if (parameter.options.contains(value)) key: value,
      },
    );
  }

  bool sameSettings(ShootingRecipe other) =>
      canonicalJson(toJson()..remove('name')) ==
      canonicalJson(other.toJson()..remove('name'));
}

class ShootingRecipeStore {
  ShootingRecipeStore(this.db);
  final Database db;
  static const prefix = 'shootingRecipe.v1.';

  Future<List<ShootingRecipe>> list() async => [
        for (final row in await db.query('app_kv',
            where: 'key LIKE ?', whereArgs: ['$prefix%'], orderBy: 'key DESC'))
          ShootingRecipe.fromJson(wireMap(jsonDecode(row['value'] as String))),
      ];

  Future<void> save(ShootingRecipe recipe) async {
    await db.insert('app_kv', {
      'key': '$prefix${DateTime.now().microsecondsSinceEpoch}',
      'value': jsonEncode(recipe.toJson()),
    });
  }

  Future<void> rememberPhotoFilm(String uri, int code, String contentHash,
      {ShootingRecipe? recipe, String? exposureRecipe}) async {
    await db.insert(
        'app_kv',
        {
          'key': 'photoFilm.v1.$uri',
          'value': jsonEncode({
            'code': code,
            'hash': contentHash,
            if (recipe != null) 'recipe': recipe.toJson(),
            if (exposureRecipe != null) 'exposureRecipe': exposureRecipe,
          }),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<
      ({
        int code,
        String hash,
        ShootingRecipe? recipe,
        String? exposureRecipe
      })?> photoFilm(String uri) async {
    final rows = await db.query('app_kv',
        where: 'key = ?', whereArgs: ['photoFilm.v1.$uri'], limit: 1);
    if (rows.isEmpty) return null;
    try {
      final value = jsonDecode(rows.single['value'] as String);
      if (value case {'code': final int code, 'hash': final String hash}) {
        final recipe = value['recipe'];
        final exposure = value['exposureRecipe'];
        return (
          code: code,
          hash: hash,
          recipe:
              recipe == null ? null : ShootingRecipe.fromJson(wireMap(recipe)),
          exposureRecipe: exposure is String ? exposure : null,
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String _captureKey(String camera, String dir, String name, int seconds) =>
      'captureRecipe.v1.${jsonEncode([camera, dir, name, seconds])}';

  Future<void> rememberCapture(
      String camera, CaptureRecord record, ShootingRecipe recipe) async {
    if (record.source != CaptureSource.app ||
        record.timeSource != TimeSource.camera) return;
    final key =
        _captureKey(camera, record.dir, record.baseName, record.wallSeconds);
    final saved = jsonEncode(recipe.toJson());
    await db.transaction((tx) async {
      final old = await tx.query('app_kv', where: 'key = ?', whereArgs: [key]);
      if (old.isEmpty) {
        await tx.insert('app_kv', {'key': key, 'value': saved});
      } else if (old.single['value'] != saved) {
        // A filename and timestamp reused by two records is ambiguous.
        await tx.update('app_kv', {'value': 'null'},
            where: 'key = ?', whereArgs: [key]);
      }
    });
  }

  Future<ShootingRecipe?> captureRecipe(
      String camera, CameraFile file, int seconds, int code) async {
    final film = recordedBuiltinFilmId(code);
    if (film == null) return null;
    final key = _captureKey(camera, file.dir, file.baseName, seconds);
    final rows = await db.query('app_kv', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    final value = jsonDecode(rows.single['value'] as String);
    if (value == null) return null;
    final recipe = ShootingRecipe.fromJson(wireMap(value));
    return recipe.film['filmId'] == film ? recipe : null;
  }
}

Map<String, String> recipeChanges(
    CameraState state, Map<String, String> target) {
  final changes = <String, String>{};
  for (final key in recipeKeys) {
    final value = target[key];
    if (value == null) continue;
    final current = state.params[key];
    if (current?.current == value) continue;
    if (current == null ||
        current.current == null ||
        !current.writable ||
        !current.options.contains(value) ||
        !current.options.contains(current.current)) {
      throw const FormatException('当前拍摄模式无法恢复配方中的设置');
    }
    changes[key] = value;
  }
  return changes;
}

Future<void> writeRecipeSettings(
    Map<String, String> changes,
    Future<WriteOutcome> Function(String, String) write,
    bool Function() sameSession) async {
  for (final MapEntry(:key, :value) in changes.entries) {
    if (!sameSession()) throw StateError('相机连接或拍摄状态已变化');
    final result = await write(key, value);
    if (result is! WriteConfirmed || result.value != value || !sameSession()) {
      throw StateError('相机未确认设置，请核对机身');
    }
  }
}

int? recordedBuiltinFilmId(int? code) {
  if (code == null) return null;
  if (code >= 0x1001 && code <= 0x104e || code >= 0x1121 && code <= 0x114e) {
    return code - 0x1000;
  }
  return null;
}
