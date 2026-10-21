import 'dart:collection';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../camera/companion/generated_contract.dart';

final Map<String, dynamic> filmContract =
    jsonDecode(companionContractJson) as Map<String, dynamic>;

Object? sortedJson(Object? value) {
  if (value is Map) {
    return SplayTreeMap<String, Object?>.from(
        value.map((k, v) => MapEntry(k as String, sortedJson(v))));
  }
  if (value is List) return value.map(sortedJson).toList();
  return value;
}

String canonicalJson(Object? value) => jsonEncode(sortedJson(value));

class FilmRecipe {
  FilmRecipe._(
      {required this.filmId,
      required this.catalogHash,
      required this.rendererHash,
      required Map<String, int> parameters,
      required this.name,
      this.customHash})
      : parameters = Map.unmodifiable(parameters);
  factory FilmRecipe.fromJson(Map<String, dynamic> json) {
    const allowed = {
      'schemaVersion',
      'filmId',
      'catalogHash',
      'rendererHash',
      'parameters',
      'name',
      'customHash'
    };
    void need(bool v) {
      if (!v) throw const FormatException('胶卷配方格式或参数不受支持');
    }

    need(json.keys.every(allowed.contains));
    need(json['schemaVersion'] == 1);
    final id = json['filmId'];
    need(id is int && id >= 1 && id <= 289);
    final hash = RegExp(r'^[a-f0-9]{64}$');
    for (final key in ['catalogHash', 'rendererHash']) {
      need(json[key] is String && hash.hasMatch(json[key] as String));
    }
    final custom = json['customHash'];
    need(custom == null || custom is String && hash.hasMatch(custom));
    need(!(id >= 79 && id <= 288) || custom != null);
    final raw = json['parameters'];
    need(raw is Map);
    final parameters = <String, int>{};
    for (final entry in (raw as Map).entries) {
      need(entry.key is String);
      final p = (filmContract['parameters'] as Map)[entry.key] as Map?;
      need(p != null);
      final v = entry.value;
      need(v is int &&
          v >= p!['min'] &&
          (v <= (p['overrides']?[id.toString()] ?? p['max'])));
      need((p!['filmIds'] == null || (p['filmIds'] as List).contains(id)) &&
          !(p['excludeFilmIds'] as List? ?? []).contains(id));
      parameters[entry.key as String] = v as int;
    }
    final name = json['name'] ?? '';
    need(name is String && name.trim().runes.length <= 24);
    return FilmRecipe._(
        filmId: id as int,
        catalogHash: json['catalogHash'] as String,
        rendererHash: json['rendererHash'] as String,
        parameters: parameters,
        name: (name as String).trim(),
        customHash: custom as String?);
  }
  final int filmId;
  final String catalogHash, rendererHash, name;
  final String? customHash;
  final Map<String, int> parameters;
  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'filmId': filmId,
        'catalogHash': catalogHash,
        'rendererHash': rendererHash,
        'parameters': parameters,
        'name': name,
        'customHash': customHash
      };
  String get fingerprint {
    final identity = toJson()..remove('name');
    return sha256.convert(utf8.encode(canonicalJson(identity))).toString();
  }
}
