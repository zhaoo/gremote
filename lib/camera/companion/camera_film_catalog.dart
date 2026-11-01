import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../film/catalog/film_catalog.dart';
import '../../film/model/film_recipe.dart';
import 'generated_camera_contract.dart';

final Map<String, dynamic> cameraContract =
    jsonDecode(cameraContractJson) as Map<String, dynamic>;
const legacyPreviewCatalogHash =
    'e0a5fe1be29c20274edd537fd234905fb6f1ac4b60a5f5b99355f43d57aa14d5';
const legacyPreviewRendererHash =
    'f2aa5411ff40808612b5c232dc854e248b0aa0890c903eb8b319a93d8acf73b2';

bool cameraParameterSupported(String key, int id) {
  final p = (cameraContract['parameters'] as Map)[key] as Map?;
  if ((cameraContract['readOnlyParameters'] as List).contains(key)) {
    return p != null;
  }
  return (id > 0 ||
          (cameraContract['readOnlyParameters'] as List).contains(key)) &&
      p != null &&
      (p['filmIds'] == null || (p['filmIds'] as List).contains(id)) &&
      !(p['excludeFilmIds'] as List? ?? []).contains(id);
}

Map<String, int> cameraDefaults(int id) => {
      for (final e in (cameraContract['parameters'] as Map).entries)
        if (cameraParameterSupported(e.key as String, id))
          e.key as String: (e.value as Map)['default'] as int
    };

/// Camera-only value. Never pass this to the pinned phone preview renderer.
class CameraFilmRecipe implements FilmRecipe {
  CameraFilmRecipe.fromJson(Map<String, dynamic> json) {
    const fields = {
      'schemaVersion',
      'filmId',
      'catalogHash',
      'rendererHash',
      'parameters',
      'name',
      'customHash'
    };
    void need(bool value) {
      if (!value) throw const FormatException('相机胶卷版本或参数不受支持');
    }

    need(json.keys.every(fields.contains) && json['schemaVersion'] == 1);
    need(json['catalogHash'] == cameraCatalogHash &&
        json['rendererHash'] == cameraRendererHash);
    final id = json['filmId'];
    need(id is int && id >= 0 && id <= 321);
    final custom = json['customHash'];
    need(custom == null ||
        custom is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(custom));
    need(id >= 79 && id <= 288 ? custom != null : custom == null);
    final raw = json['parameters'];
    need(raw is Map);
    final p = <String, int>{};
    for (final e in (raw as Map).entries) {
      need(e.key is String &&
          cameraParameterSupported(e.key as String, id as int));
      final rule = (cameraContract['parameters'] as Map)[e.key] as Map;
      need(e.value is int &&
          e.value >= rule['min'] &&
          e.value <= (rule['overrides']?[id.toString()] ?? rule['max']));
      p[e.key as String] = e.value as int;
    }
    final label = json['name'] ?? '';
    need(label is String && label.trim().runes.length <= 48);
    filmId = id as int;
    parameters = Map.unmodifiable(p);
    name = (label as String).trim();
    customHash = custom as String?;
  }
  @override
  late final int filmId;
  @override
  late final Map<String, int> parameters;
  @override
  late final String name;
  @override
  late final String? customHash;
  @override
  String get catalogHash => cameraCatalogHash;
  @override
  String get rendererHash => cameraRendererHash;
  @override
  Map<String, int> get resolvedParameters =>
      {...cameraDefaults(filmId), ...parameters};
  @override
  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'filmId': filmId,
        'catalogHash': catalogHash,
        'rendererHash': rendererHash,
        'parameters': parameters,
        'name': name,
        'customHash': customHash
      };
  @override
  String get fingerprint => sha256
      .convert(utf8.encode(canonicalJson(toJson()..remove('name'))))
      .toString();
}

class CameraFilmCatalog extends FilmCatalog {
  CameraFilmCatalog.fromJson(Map<String, dynamic> value)
      : super.fromJson(value) {
    final identity = Map<String, dynamic>.from(value)..remove('hash');
    if (hash != cameraCatalogHash ||
        rendererHash != cameraRendererHash ||
        sha256.convert(utf8.encode(canonicalJson(identity))).toString() !=
            hash) {
      throw const FormatException('相机目录校验失败');
    }
  }
  @override
  CameraFilmRecipe recipe(int id,
      {String? name, Map<String, int> parameters = const {}}) {
    final definition = film(id);
    return CameraFilmRecipe.fromJson({
      'schemaVersion': 1,
      'filmId': id,
      'catalogHash': hash,
      'rendererHash': rendererHash,
      'name': name ?? definition.name,
      'parameters': {...cameraDefaults(id), ...parameters}
    });
  }

  CameraFilmRecipe forTarget(FilmRecipe source, Map<String, Object?> target) {
    film(source
        .filmId); // Only the current visible stable IDs can be newly loaded.
    Map<String, int> parameters;
    if (source is CameraFilmRecipe) {
      // Revalidate the value and exact generation before it becomes a patch.
      parameters =
          CameraFilmRecipe.fromJson(Map<String, dynamic>.from(source.toJson()))
              .resolvedParameters;
    } else {
      if (source.catalogHash != legacyPreviewCatalogHash ||
          source.rendererHash != legacyPreviewRendererHash ||
          source.customHash != null ||
          !((source.filmId >= 33 && source.filmId <= 78) ||
              source.filmId == 289)) {
        throw const FormatException('此旧配方无法转换，请在相机目录重新选择');
      }
      final old = source.resolvedParameters;
      if ((old['leakGain'] ?? 0) != 0 || (old['grainSize'] ?? 1) != 1) {
        throw const FormatException('旧配方的漏光或颗粒尺寸已不支持，请先关闭这些效果');
      }
      parameters = {...cameraDefaults(source.filmId), ...old};
      parameters['haloProfile'] = (old['haloGain'] ?? 0) > 0 ? 4 : 6;
    }
    final retired =
        (cameraContract['readOnlyParameters'] as List).cast<String>();
    final prior = (target['parameters'] as Map?) ?? {};
    for (final key in retired) {
      parameters.remove(key);
      if (cameraParameterSupported(key, source.filmId)) {
        if (!prior.containsKey(key)) {
          throw const FormatException('槽位保留参数缺失，请重新读取相机');
        }
        parameters[key] = prior[key] as int;
      }
    }
    if (source.filmId == 289) {
      parameters['leakGain'] =
          0; // Native Charmera transition clears this retired effect.
    }
    return CameraFilmRecipe.fromJson({
      'schemaVersion': 1,
      'filmId': source.filmId,
      'catalogHash': hash,
      'rendererHash': rendererHash,
      'parameters': parameters,
      'customHash': source.customHash,
      'name': source.name
    });
  }
}
