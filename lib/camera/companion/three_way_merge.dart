import '../../film/model/film_recipe.dart';
import 'companion_protocol.dart';
import 'camera_film_catalog.dart';
import 'generated_camera_contract.dart';

enum ConflictChoice { local, remote, keepBoth }

class SyncConflict {
  const SyncConflict(
      {required this.path,
      required this.base,
      required this.local,
      required this.remote});
  final String path;
  final Object? base, local, remote;
}

const _missing = Object();

class MergeResult {
  MergeResult._(
      {required this.merged,
      required this.conflicts,
      required this.readOnly,
      required this.keepLocalSlots,
      required Map<String, Object?> base,
      required Map<String, Object?> local,
      required Map<String, Object?> remote,
      required CompanionCapabilities capabilities,
      required Map<String, ConflictChoice> choices})
      : _base = base,
        _local = local,
        _remote = remote,
        _capabilities = capabilities,
        _choices = choices;
  final Map<String, Object?> merged;
  final List<SyncConflict> conflicts;
  final Set<int> keepLocalSlots;
  final bool readOnly;
  final Map<String, Object?> _base, _local, _remote;
  final CompanionCapabilities _capabilities;
  final Map<String, ConflictChoice> _choices;
  bool get resolved => conflicts.every((c) => _choices.containsKey(c.path));
  MergeResult resolve(Map<String, ConflictChoice> choices) =>
      _merge(_base, _local, _remote, _capabilities, {..._choices, ...choices});
}

bool _same(Object? a, Object? b) =>
    identical(a, _missing) || identical(b, _missing)
        ? identical(a, b)
        : canonicalJson(a) == canonicalJson(b);
bool knownCompanionConfig(Map<String, Object?> config,
    {Map<String, dynamic>? contract}) {
  contract ??= companionContract;
  final modern = (contract['stateSchema'] ?? 1) == 2;
  final seen = <int>{};
  var emptySeen = false;
  if (config.keys.any((k) => !{'slots', 'globals'}.contains(k)) ||
      config['slots'] is! List ||
      (config['slots'] as List).length != contract['slotCount'] ||
      config['globals'] is! Map) return false;
  final globals = wireMap(config['globals']);
  const ranges = {
    'stamp': 2,
    'format': 3,
    'corner': 3,
    'color': 3,
    'filmNameStamp': 1
  };
  if (globals.length != ranges.length ||
      globals.entries.any((e) =>
          !ranges.containsKey(e.key) ||
          e.value is! int ||
          (e.value as int) < 0 ||
          (e.value as int) > ranges[e.key]!)) return false;
  for (final raw in config['slots'] as List) {
    final slot = wireMap(raw);
    if (slot.keys
        .any((k) => !{'filmId', 'parameters', 'customHash'}.contains(k))) {
      return false;
    }
    try {
      final id = slot['filmId'];
      if (modern && id is int) {
        if (id == 0) {
          emptySeen = true;
        } else if (emptySeen || !seen.add(id)) {
          return false;
        }
      }
      final value = <String, dynamic>{
        'schemaVersion': 1,
        ...slot,
        'catalogHash': modern ? cameraCatalogHash : '0' * 64,
        'rendererHash': modern ? cameraRendererHash : '0' * 64
      };
      if (modern) {
        CameraFilmRecipe.fromJson(value);
      } else {
        FilmRecipe.fromJson(value);
      }
    } on FormatException {
      return false;
    }
  }
  return true;
}

MergeResult threeWayMerge(
        {required Map<String, Object?> base,
        required Map<String, Object?> local,
        required Map<String, Object?> remote,
        required CompanionCapabilities capabilities}) =>
    _merge(wireMap(base), wireMap(local), wireMap(remote), capabilities, {});
MergeResult _merge(
    Map<String, Object?> base,
    Map<String, Object?> local,
    Map<String, Object?> remote,
    CompanionCapabilities capabilities,
    Map<String, ConflictChoice> choices) {
  final conflicts = <SyncConflict>[], keepSlots = <int>{};
  Object? walk(Object? b, Object? l, Object? r, String path) {
    if (_same(l, r)) return l;
    if (_same(l, b)) return r;
    if (_same(r, b)) return l;
    if (b is Map && l is Map && r is Map) {
      final out = <String, Object?>{},
          keys = <String>{
            ...b.keys.cast<String>(),
            ...l.keys.cast<String>(),
            ...r.keys.cast<String>()
          };
      for (final key in keys) {
        final value = walk(
            b.containsKey(key) ? b[key] : _missing,
            l.containsKey(key) ? l[key] : _missing,
            r.containsKey(key) ? r[key] : _missing,
            path.isEmpty ? key : '$path.$key');
        if (!identical(value, _missing)) out[key] = value;
      }
      return out;
    }
    if (b is List &&
        l is List &&
        r is List &&
        b.length == l.length &&
        b.length == r.length) {
      return List.generate(b.length, (i) => walk(b[i], l[i], r[i], '$path.$i'));
    }
    conflicts.add(SyncConflict(
        path: path,
        base: identical(b, _missing) ? null : b,
        local: identical(l, _missing) ? null : l,
        remote: identical(r, _missing) ? null : r));
    final choice = choices[path];
    if (choice == ConflictChoice.keepBoth && path.startsWith('slots.')) {
      final index = int.tryParse(path.split('.')[1]);
      if (index != null) keepSlots.add(index);
    }
    return choice == ConflictChoice.local ? l : r;
  }

  final result =
      Map<String, Object?>.from(walk(base, local, remote, '') as Map);
  if (keepSlots.isNotEmpty) {
    final slots = List<Object?>.from(result['slots'] as List);
    for (final slot in keepSlots) {
      slots[slot] = (remote['slots'] as List)[slot];
    }
    result['slots'] = slots;
  }
  final merged = wireMap(result);
  return MergeResult._(
      merged: merged,
      conflicts: List.unmodifiable(conflicts),
      readOnly: capabilities.hasUnknownFields ||
          !knownCompanionConfig(base, contract: capabilities.contract) ||
          !knownCompanionConfig(local, contract: capabilities.contract) ||
          !knownCompanionConfig(remote, contract: capabilities.contract) ||
          !knownCompanionConfig(merged, contract: capabilities.contract),
      keepLocalSlots: Set.unmodifiable(keepSlots),
      base: base,
      local: local,
      remote: remote,
      capabilities: capabilities,
      choices: Map.unmodifiable(choices));
}
