import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../film/catalog/film_catalog.dart';
import '../../film/model/film_recipe.dart';
import 'generated_camera_contract.dart';
import 'generated_full_camera_contract.dart';
import 'generated_leica_camera_contract.dart';

final Map<String, dynamic> cameraContract =
    _freezeMap(jsonDecode(cameraContractJson) as Map);
const legacyPreviewCatalogHash =
    'e0a5fe1be29c20274edd537fd234905fb6f1ac4b60a5f5b99355f43d57aa14d5';
const legacyPreviewRendererHash =
    'f2aa5411ff40808612b5c232dc854e248b0aa0890c903eb8b319a93d8acf73b2';

/// Exact bundled identities only. A website cache can never register a profile.
class CameraFilmProfile {
  CameraFilmProfile._(
      this.catalogHash, this.rendererHash, this.contract, this.versionLabel);
  final String catalogHash, rendererHash, versionLabel;
  final Map<String, dynamic> contract;
  bool get isLatest =>
      catalogHash == cameraCatalogHash && rendererHash == cameraRendererHash;
}

Map<String, dynamic> _freezeMap(Map value) =>
    Map<String, dynamic>.unmodifiable(value.map((k, v) => MapEntry(
        k as String,
        v is Map
            ? _freezeMap(v)
            : v is List
                ? _freezeList(v)
                : v)));
List<dynamic> _freezeList(List value) =>
    List<dynamic>.unmodifiable(value.map((v) => v is Map
        ? _freezeMap(v)
        : v is List
            ? _freezeList(v)
            : v));

// This M10V release changes the renderer while retaining the camera catalog
// entries and companion parameter contract.
const coordinatedCameraCatalogHash =
    'cf7032d8db4c13c266229084f323e231bfea0fc50e3ad1e9966f25d2f4ddfb99';
const coordinatedCameraRendererHash =
    '8860d923d8a0bb65ac9530c52d89d140a5345505230c165e0c0c78f9f1972fba';

// Public GR III GRemote package. Pinned to the firmware/service receipts and
// the independently regenerated catalog; its wire contract still ends at 326.
const publicGr3CameraCatalogHash =
    'dec78e808816dd21e7e6225a7a3c539699bd0572bb018b719e7fcc5c328be696';
const publicGr3CameraRendererHash =
    'db7fdff7b13e23447f4a58c561b92813319acf249b8922f75b4ffdad3bb74f30';

const fullGr3CameraCatalogHash =
    '1b1b34c3da9b80de854eae3ad9fc3e85ffee5687f0e28fead0504129ff6294e8';
const fullGr3CameraRendererHash =
    'bcef872c4ff5789a34b47f4c1becc31303a55b95f381c032d9b73bc7cc4c1ae7';

const _leicaRc1CatalogHash =
    'acfdebf15b861f78afed4b7104e0d32ba2e9c5bb36beb513c9b8286891074e19';
const _leicaRc1RendererHash =
    '6a7f612c85cf05ebd9f293131fa3d578df62bb89e3cba23d25b059bedb29c6c1';

const installedCameraCatalogHash =
    '653acf3c1b04db0ea2dd10114a1306b78bb4b584534945be8f9de9da25ebab4a';
const installedCameraRendererHash =
    '80a4d357be06ff0e9510a20bef1035dc3e848ec585bd5d5cdee466c3980506a4';
final List<CameraFilmProfile> trustedCameraFilmProfiles = List.unmodifiable([
  CameraFilmProfile._(
      cameraCatalogHash, cameraRendererHash, cameraContract, '机身版本 · 当前配套'),
  CameraFilmProfile._(coordinatedCameraCatalogHash,
      coordinatedCameraRendererHash, cameraContract, '机身版本 · 2026.11.05.1'),
  CameraFilmProfile._(publicGr3CameraCatalogHash, publicGr3CameraRendererHash,
      cameraContract, '机身版本 · GR III 公开配套'),
  CameraFilmProfile._(fullGr3CameraCatalogHash, fullGr3CameraRendererHash,
      _freezeMap(jsonDecode(fullCameraContractJson) as Map),
      '机身版本 · GR III 全功能 2026.11.08'),
  CameraFilmProfile._(leicaCameraCatalogHash, leicaCameraRendererHash,
      _freezeMap(jsonDecode(leicaCameraContractJson) as Map),
      '机身版本 · GR III 莱卡效果测试版'),
  // RC1 extends the 2026.11.08 wire contract only by adding film IDs.
  CameraFilmProfile._(
      _leicaRc1CatalogHash,
      _leicaRc1RendererHash,
      _freezeMap(
          (jsonDecode(fullCameraContractJson) as Map)..['maximumFilmId'] = 334),
      '机身版本 · GR III 莱卡效果 RC1'),
  CameraFilmProfile._(
      installedCameraCatalogHash,
      installedCameraRendererHash,
      _freezeMap(jsonDecode(_installedCameraContractJson) as Map),
      '机身版本 · 03db1c70'),
]);
CameraFilmProfile? resolveCameraFilmProfile(Object? catalog, Object? renderer) {
  for (final profile in trustedCameraFilmProfiles) {
    if (profile.catalogHash == catalog && profile.rendererHash == renderer) {
      return profile;
    }
  }
  return null;
}

CameraFilmProfile? cameraFilmProfileForContract(Map<String, dynamic> contract) {
  final identity = canonicalJson(contract);
  for (final profile in trustedCameraFilmProfiles) {
    if (canonicalJson(profile.contract) == identity) return profile;
  }
  return null;
}

Map<String, dynamic> _displayCatalog(Map<String, dynamic> value) {
  final profile =
      resolveCameraFilmProfile(value['hash'], value['rendererHash']);
  if (profile == null) return value;
  // The raw catalog identity is checked separately. Only offer films that the
  // matching service's write contract can actually represent.
  return {
    ...value,
    'entries': [
      for (final entry in value['entries'] as List)
        if (entry['id'] <= profile.contract['maximumFilmId'])
          {
            ...entry as Map,
            if (value['hash'] == installedCameraCatalogHash)
              'icon':
                  'assets/films/camera-profiles/old-icons/${entry['id']}.png'
          }
    ]
  };
}

bool cameraParameterSupported(String key, int id,
    {Map<String, dynamic>? contract}) {
  final rules = contract ?? cameraContract;
  final p = (rules['parameters'] as Map)[key] as Map?;
  if ((rules['readOnlyParameters'] as List).contains(key)) {
    return p != null;
  }
  return (id > 0 || (rules['readOnlyParameters'] as List).contains(key)) &&
      p != null &&
      (p['filmIds'] == null || (p['filmIds'] as List).contains(id)) &&
      !(p['excludeFilmIds'] as List? ?? []).contains(id);
}

Map<String, int> cameraDefaults(int id, {Map<String, dynamic>? contract}) => {
      for (final e
          in ((contract ?? cameraContract)['parameters'] as Map).entries)
        if (cameraParameterSupported(e.key as String, id, contract: contract))
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
    final selected =
        resolveCameraFilmProfile(json['catalogHash'], json['rendererHash']);
    need(selected != null);
    profile = selected!;
    final contract = profile.contract;
    final id = json['filmId'];
    need(id is int && id >= 0 && id <= (contract['maximumFilmId'] as int));
    final custom = json['customHash'];
    need(custom == null ||
        custom is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(custom));
    need(id >= 79 && id <= 288 ? custom != null : custom == null);
    final raw = json['parameters'];
    need(raw is Map);
    final p = <String, int>{};
    for (final e in (raw as Map).entries) {
      need(e.key is String &&
          cameraParameterSupported(e.key as String, id as int,
              contract: contract));
      final rule = (contract['parameters'] as Map)[e.key] as Map;
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
  late final CameraFilmProfile profile;
  @override
  late final int filmId;
  @override
  late final Map<String, int> parameters;
  @override
  late final String name;
  @override
  late final String? customHash;
  @override
  String get catalogHash => profile.catalogHash;
  @override
  String get rendererHash => profile.rendererHash;
  @override
  Map<String, int> get resolvedParameters =>
      {...cameraDefaults(filmId, contract: profile.contract), ...parameters};
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
      : super.fromJson(_displayCatalog(value)) {
    final identity = Map<String, dynamic>.from(value)..remove('hash');
    final selected = resolveCameraFilmProfile(hash, rendererHash);
    if (selected == null ||
        sha256.convert(utf8.encode(canonicalJson(identity))).toString() !=
            hash) {
      throw const FormatException('相机目录校验失败');
    }
    profile = selected;
  }
  late final CameraFilmProfile profile;
  Map<String, dynamic> get contract => profile.contract;
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
      'parameters': {...cameraDefaults(id, contract: contract), ...parameters}
    });
  }

  CameraFilmRecipe forTarget(FilmRecipe source, Map<String, Object?> target) {
    film(source
        .filmId); // Only the current visible stable IDs can be newly loaded.
    Map<String, int> parameters;
    if (source is CameraFilmRecipe) {
      if (source.catalogHash != hash || source.rendererHash != rendererHash) {
        throw const FormatException('相机配方属于其他机身版本，请在当前机身目录重新选择');
      }
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
      parameters = {
        ...cameraDefaults(source.filmId, contract: contract),
        ...old
      };
      parameters['haloProfile'] = (old['haloGain'] ?? 0) > 0 ? 4 : 6;
    }
    final retired = (contract['readOnlyParameters'] as List).cast<String>();
    final prior = (target['parameters'] as Map?) ?? {};
    for (final key in retired) {
      parameters.remove(key);
      if (cameraParameterSupported(key, source.filmId, contract: contract)) {
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

// Extracted from the SHA-256 verified 03db1c70 delivery APK; see bundled provenance.
const _installedCameraContractJson =
    r'''{"protocol":1,"recipeSchema":1,"slotCount":10,"port":18743,"officialFirmwareSha256":"d6a3c9c288d784080e7b283222ecdd8752adfeed6faa36dab44f73115354bfd4","limits":{"jsonBytes":16384,"chunkBytes":16384,"recordBytes":12288,"stagingBytes":65536,"pollMilliseconds":2000,"previewEdge":960,"previewFallbackEdge":640,"previewCacheBytes":50331648,"contactSheetPageSize":24,"filmChunkBytes":4096},"errors":["unauthorized","unsupportedProtocol","unsupportedModel","incompatibleRenderer","invalidRecipe","busy","revisionConflict","storeFailed","readbackMismatch","bridgeUnavailable","resultUnknown"],"parameters":{"grain":{"min":0,"max":3,"default":0,"label":"颗粒","excludeFilmIds":[289]},"grainSize":{"min":0,"max":2,"default":1,"label":"颗粒尺寸","excludeFilmIds":[289]},"haloGain":{"min":0,"max":8,"default":0,"label":"光晕强度"},"haloSpread":{"min":0,"max":8,"default":3,"label":"扩散范围"},"haloThreshold":{"min":0,"max":8,"default":5,"label":"高光阈值"},"haloProfile":{"min":0,"max":6,"default":6,"label":"光晕模式"},"leakGain":{"min":0,"max":8,"default":0,"label":"漏光强度","excludeFilmIds":[289]},"leakPosition":{"min":0,"max":5,"default":0,"label":"漏光位置","excludeFilmIds":[289]},"leakSpread":{"min":0,"max":8,"default":4,"label":"漏光范围","excludeFilmIds":[289]},"leakVariation":{"min":0,"max":1,"default":0,"label":"漏光变化","excludeFilmIds":[289]},"filmExposure":{"min":0,"max":2,"default":0,"label":"模拟曝光","filmIds":[67,68],"overrides":{"67":1}},"charmeraColor":{"min":0,"max":3,"default":0,"label":"机身颜色","filmIds":[289]}},"capabilities":{"readState":false,"writeState":false,"uploadFilm":false,"captureEvidence":false},"routes":{"capabilities":"/m10v/v1/capabilities","state":"/m10v/v1/state","operations":"/m10v/v1/operations","filmStage":"/m10v/v1/films/stage"},"authentication":{"algorithm":"HMAC-SHA256","maxSessions":8,"sequenceWindow":64,"bootstrapNonces":128,"receiptCount":32,"requestCanonical":"method\\npath\\nbootId\\nsessionId\\nsequence\\nnonce\\nhex(SHA256(body))","responseCanonical":"RESPONSE\\nmethod\\npath\\nbootId\\nsessionId\\nsequence\\nnonce\\nstatus\\nhex(SHA256(body))","responseSignatureHeader":"X-M10V-Response-Signature"},"filmTransfer":{"schema":"m10v.film-transfer/v1","model":"GR III","recordBytes":12288,"chunkBytes":4096,"stageTargetSlotRequired":true,"bankScope":"per-slot","chunkHashHeader":"X-M10V-Chunk-Hash","readOnlyStatusRoute":"/m10v/v1/films/stage/{uploadId}"},"stateSchema":2,"journal":{"version":5,"bytes":184,"crcOffset":180},"maximumFilmId":321,"readOnlyParameters":["grainSize","leakGain","leakPosition","leakSpread","leakVariation"]}''';
