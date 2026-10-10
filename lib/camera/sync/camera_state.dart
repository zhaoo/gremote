import 'package:meta/meta.dart';

import '../params/camera_param.dart';
import '../protocol/props_parser.dart';

enum SyncMode { offline, polling, webSocket }

/// Everything the UI knows about the camera; only camera readback mutates
/// [params].
@immutable
class CameraState {
  const CameraState({
    this.params = const {},
    this.status = const CameraStatus(),
    this.syncMode = SyncMode.offline,
    this.writesEnabled = true,
    this.pending = const {},
    this.keyTypes = const {},
  });

  static const offline = CameraState();

  /// Wire key → parameter (known keys and extras).
  final Map<String, CameraParam> params;
  final CameraStatus status;
  final SyncMode syncMode;
  final bool writesEnabled;

  /// Wire key → value the UI asked for and the camera has not confirmed.
  final Map<String, String> pending;
  final Map<String, String> keyTypes;

  bool get online => syncMode != SyncMode.offline;

  CameraParam? param(ParamKey key) => params[key.wireKey];

  String? value(ParamKey key) => params[key.wireKey]?.current;

  /// Parameters without a dedicated control that still expose a list.
  Iterable<CameraParam> get extras =>
      params.values.where((p) => p.key == null && p.options.isNotEmpty);

  /// Merges a full or partial props payload.
  CameraState applyProps(ParsedProps parsed) {
    final next = {...params};
    for (final MapEntry(:key, value: incoming) in parsed.params.entries) {
      final existing = next[key];
      if (existing != null) {
        next[key] = existing.copyWith(
          current: incoming.current,
          options: incoming.options,
        );
      } else if (ParamKey.fromWire(key) != null ||
          (incoming.current != null && incoming.options != null)) {
        next[key] = CameraParam.forWire(
          key,
          current: incoming.current,
          options: incoming.options ?? const [],
        );
      }
    }
    return copyWith(
      params: next,
      status: status.merge(parsed.status),
      keyTypes: {...keyTypes, ...parsed.keyTypes},
    );
  }

  CameraState copyWith({
    Map<String, CameraParam>? params,
    CameraStatus? status,
    SyncMode? syncMode,
    bool? writesEnabled,
    Map<String, String>? pending,
    Map<String, String>? keyTypes,
  }) =>
      CameraState(
        params: params ?? this.params,
        status: status ?? this.status,
        syncMode: syncMode ?? this.syncMode,
        writesEnabled: writesEnabled ?? this.writesEnabled,
        pending: pending ?? this.pending,
        keyTypes: keyTypes ?? this.keyTypes,
      );
}
